-module(ates_auth).

-behaviour(gen_server).

-include_lib("brod/include/brod.hrl").

-define(KAFKA_PARTITION, 0).
-define(KAFKA_KEY, <<"key0">>).

-define(BROD_CLIENT, brod_client).

-define(TOPIC_ACCOUNT_CREATING, <<"account_creating">>).

-define(EVENT_AUTH_ACC_CREATED, <<"AuthAccountCreated">>).

%% API

-export([start_link/0]).

-export([create_account/1]).

%% Callbacks

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).

%% API

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

create_account(Params) ->
    gen_server:call(?MODULE, {create_account, Params}).

%% Callbacks

init([]) ->
    io:fwrite("~p<~p> Starting ates_auth..~n", [self(), ?MODULE]),
    application:ensure_all_started(jwt),
    io:fwrite("jwt started..~n", []),
    application:ensure_all_started(brod),
    io:fwrite("brod started..~n", []),
    application:ensure_all_started(cowboy),
    io:fwrite("cowboy started..~n", []),
    Endpoints = [
        {"/api/v1/account/", http_handler_account, []}
    ],
    Dispatch = cowboy_router:compile([{'_', Endpoints}]),
    {ok, _} = cowboy:start_clear(
        auth_http_listener,
        [{port, 14100}],
        #{env => #{dispatch => Dispatch}}
    ),
    io:fwrite("Init DB..~n", []),
    DbOpts = [
        {type, set},
        {file, "auth_db.dat"}
    ],
    {ok, auth_db} = dets:open_file(auth_db, DbOpts),
    case brod_client_init() of
        ok ->
            io:fwrite("ates_auth started.~n", []),
            {ok, #{}};
        {error, Error} ->
            io:fwrite("ates_auth start failed with Error=~p~n", [Error]),
            throw("Failed to start ates_auth events client")
    end.

handle_call({create_account, Params}, _From, State) ->
    #{
        popug_name := PopugName,
        popug_pass := PopugPass
    } = Params,
    io:fwrite("Creating account for popug Name=~0p Pass=~0p~n", [PopugName, PopugPass]),
    PopugID = generate_uuid(),
    Claims = [
        {popug_id, PopugID},
        {popug_name, PopugName}
    ],
    {ok, Token} = jwt:encode(<<"HS256">>, Claims, PopugPass),
    true = dets:insert_new(auth_db, {PopugID, Token}),
    io:fwrite("Generated auth data for popug Name=~0p Token=~p~n", [PopugName, Token]),
    EventData = #{
        popug_id => PopugID,
        popug_name =>PopugName
    },
    Event = brod_event_create(?EVENT_AUTH_ACC_CREATED, EventData),
    ok = brod_event_produce(Event),
    io:fwrite("Produced Event=~p Data=~p~n", [?EVENT_AUTH_ACC_CREATED, EventData]),
    {reply, ok, State};
handle_call(Request, From, State) ->
    io:fwrite("~p<~p> Unhandled call Request=~p From=~p~n", [self(), ?MODULE, Request, From]),
    {noreply, State}.

handle_cast(Request, State) ->
    io:fwrite("~p<~p> Unhandled cast Request=~p~n", [self(), ?MODULE, Request]),
    {noreply, State}.

handle_info({_From, #kafka_message_set{topic = ?TOPIC_ACCOUNT_CREATING, messages = Messages}}, State) ->
    ok = handle_kafka_messages(Messages),
    {noreply, State};
handle_info(Message, State) ->
    io:fwrite("~p<~p> Unhandled info Message=~p~n", [self(), ?MODULE, Message]),
    {noreply, State}.

%% Internal functions

generate_uuid() ->
    UuidState = uuid:new(self()),
    {UUID, _} = uuid:get_v1(UuidState),
    list_to_binary(uuid:uuid_to_string(UUID)).

brod_client_init() ->
    KafkaBootstrapEndpoints = [{"localhost", 9092}],
    io:fwrite("Starting brod client..~n", []),
    ok = brod:start_client(KafkaBootstrapEndpoints, ?BROD_CLIENT),
    io:fwrite("Starting brod consumer..~n", []),
    ok = brod:start_consumer(?BROD_CLIENT, ?TOPIC_ACCOUNT_CREATING, []),
    {ok, _ConsumerPid} = brod:subscribe(?BROD_CLIENT, self(), ?TOPIC_ACCOUNT_CREATING, ?KAFKA_PARTITION, []),
    io:fwrite("Brod consumer started successfully~n", []),
    io:fwrite("Starting brod event producer for Topic=~p~n", [?TOPIC_ACCOUNT_CREATING]),
    case brod:start_producer(?BROD_CLIENT, ?TOPIC_ACCOUNT_CREATING, [{max_retries, 5}]) of
        ok ->
            io:fwrite("Brod producer for Topic=~p started successfully.~n", [?TOPIC_ACCOUNT_CREATING]),
            ok;
        unknown_topic_or_partition ->
            io:fwrite("Brod producer start error unknown_topic_or_partition Topic=~p, retry..~n", [?TOPIC_ACCOUNT_CREATING]),
            case brod:start_producer(?BROD_CLIENT, ?TOPIC_ACCOUNT_CREATING, [{max_retries, 5}]) of
                ok ->
                    io:fwrite("Brod producer for Topic=~p started successfully.~n", [?TOPIC_ACCOUNT_CREATING]),
                    ok;
                {error, Error} ->
                    io:fwrite("Failed to start brod producer for Topic=~p Error=~p~n", [?TOPIC_ACCOUNT_CREATING, Error]),
                    {error, start_brod_producer}
            end;
        {error, Error} ->
            io:fwrite("Failed to start brod producer for Topic=~p Error=~p~n", [?TOPIC_ACCOUNT_CREATING, Error]),
            {error, start_brod_producer}
    end.

brod_event_create(Event, Data) ->
    ok = brod_event_check(Event),
    term_to_binary({Event, Data}, [compressed]).

brod_event_check(?EVENT_AUTH_ACC_CREATED) ->
    ok;
brod_event_check(_NotImplemented) ->
    not_impl.

brod_event_produce(EventData) ->
    ok = brod:produce_sync(
        ?BROD_CLIENT,
        ?TOPIC_ACCOUNT_CREATING,
        ?KAFKA_PARTITION,
        ?KAFKA_KEY,
        EventData
    ).

handle_kafka_messages(Messages) ->
    lists:foreach(
        fun(Message) -> handle_kafka_message(Message) end,
        Messages
    ).

handle_kafka_message(#kafka_message{value = Value}) ->
    {Event, EventData} = binary_to_term(Value),
    io:fwrite("Got kafka message Event=~p Data=~p~n", [Event, EventData]),
    handle_kafka_message(Event, EventData),
    ok.

handle_kafka_message(<<"AccounterAccountCreated">>, EventData) ->
    on_accounter_account_created(EventData);
handle_kafka_message(NotHandled, _EventData) ->
    io:fwrite("Skip not handled Event=~p~n", [NotHandled]),
    ok.

on_accounter_account_created(#{popug_id := PopugID}) ->
    [Popug] = dets:lookup(auth_db, PopugID),
    #{popug_id := PopugID} = Popug,
    io:fwrite("Check accounter creation for popug ID=~p ok~n", [PopugID]),
    ok.
