-module(ates_accounter).

-behaviour(gen_server).

-include_lib("brod/include/brod.hrl").

-define(KAFKA_PARTITION, 0).
-define(KAFKA_KEY, <<"key0">>).

-define(BROD_CLIENT, brod_client).

-define(TOPIC_ACCOUNT_CREATING, <<"account_creating">>).
-define(TOPIC_ACCOUNT_BALANCE, <<"account_balance">>).
-define(TOPIC_TASKS, <<"tasks">>).

-define(EVENT_AUTH_ACC_CREATED, <<"AuthAccountCreated">>).
-define(EVENT_ACCOUNTER_ACC_CREATED, <<"AccounterAccountCreated">>).
-define(EVENT_ACCOUNTER_BALANCE_CHANGED, <<"AccounterBalanceChanged">>).
-define(EVENT_TASK_ASSIGNED, <<"TaskAssigned">>).

%% API

-export([start_link/0]).
-export([handle_event/1]).

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

handle_event(Event) ->
    gen_server:cast(?MODULE, {event, Event}).

%% Callbacks

init([]) ->
    rand:seed(),
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
        accounter_http_listener,
        [{port, 14101}],
        #{env => #{dispatch => Dispatch}}
    ),
    io:fwrite("Init DB..~n", []),
    DbOpts = [
        {type, set},
        {file, "accounter_db.dat"}
    ],
    {ok, accounter_db} = dets:open_file(accounter_db, DbOpts),
    case brod_client_init() of
        ok ->
            io:fwrite("ates_accounter started.~n", []),
            {ok, #{}};
        {error, Error} ->
            io:fwrite("ates_accounter start failed with Error=~p~n", [Error]),
            throw("Failed to start ates_accounter events client")
    end.

handle_call(Request, From, State) ->
    io:fwrite("~p<~p> Unhandled call Request=~p From=~p~n", [self(), ?MODULE, Request, From]),
    {noreply, State}.

handle_cast({event, Event}, State) ->
    ok = handle_event(Event),
    {noreply, State};
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

brod_client_init() ->
    KafkaBootstrapEndpoints = [{"localhost", 9092}],
    io:fwrite("Starting brod client..~n", []),
    ok = brod:start_client(KafkaBootstrapEndpoints, ?BROD_CLIENT),
    io:fwrite("Starting brod consumer..~n", []),
    ok = brod:start_consumer(?BROD_CLIENT, ?TOPIC_ACCOUNT_CREATING, []),
    {ok, _ConsumerPid1} = brod:subscribe(?BROD_CLIENT, self(), ?TOPIC_ACCOUNT_CREATING, ?KAFKA_PARTITION, []),
    ok = brod:start_consumer(?BROD_CLIENT, ?TOPIC_TASKS, []),
    {ok, _ConsumerPid2} = brod:subscribe(?BROD_CLIENT, self(), ?TOPIC_TASKS, ?KAFKA_PARTITION, []),
    io:fwrite("Brod consumers started successfully~n", []),
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

brod_event_check(?EVENT_ACCOUNTER_ACC_CREATED) ->
    ok;
brod_event_check(_NotImplemented) ->
    not_impl.

brod_event_produce(Topic, EventData) ->
    ok = brod:produce_sync(
        ?BROD_CLIENT,
        Topic,
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
    io:fwrite("Got kafka message Event=~p Data=~p", [Event, EventData]),
    handle_kafka_message(Event, EventData),
    ok.

handle_kafka_message(?EVENT_AUTH_ACC_CREATED, EventData) ->
    on_auth_account_created(EventData);
handle_kafka_message(?EVENT_TASK_ASSIGNED, EventData) ->
    on_task_assigned(EventData);
handle_kafka_message(NotHandled, _EventData) ->
    io:fwrite("Skip not handled Event=~p~n", [NotHandled]),
    ok.

on_auth_account_created(#{popug_name := PopugName, popug_id := PopugID}) ->
    io:fwrite("Creating account for popug Name=~p ID=~p~n", [PopugName, PopugID]),
    AccountData = #{
        popug_id => PopugID,
        popug_name => PopugName,
        audit_log => [],
        balance => 0,
        balance_daily => 0
    },
    true = dets:insert_new(accounter_db, {PopugID, AccountData}),
    io:fwrite("Created account for popug Name=~p~n", [PopugName]),
    EventData = #{
        version => 1,
        popug_id => PopugID
    },
    Event = brod_event_create(?EVENT_ACCOUNTER_ACC_CREATED, EventData),
    ok = brod_event_produce(?TOPIC_ACCOUNT_CREATING, Event),
    io:fwrite("Produced Event=~p Data=~p~n", [?EVENT_ACCOUNTER_ACC_CREATED, EventData]),
    ok.

on_task_assigned(#{task_id := TaskID, popug_id := PopugID, tax := Tax}) ->
    io:fwrite("Got event of task assigned for PopugID=~0p: TaskID=~0p Tax=~0p~n", [PopugID, TaskID, Tax]),
    [AccountData] = dets:lookup(accounter_db, PopugID),
    io:fwrite("Got account data for PopugID=~0p~n", [PopugID]),
    #{
        audit_log := AuditLog,
        balance := Balance,
        balance_daily := BalanceDaily
    } = AccountData,
    BalanceChange = -Tax,
    Balance1 = Balance + BalanceChange,
    BalanceDaily1 = BalanceDaily + BalanceChange,
    AuditLog1 =[{task_assigned, TaskID} | AuditLog],
    AuditLog2 =[{tax, Tax} | AuditLog1],
    AccountData1 = AccountData#{
        audit_log := AuditLog2,
        balance := Balance1,
        balance_daily := BalanceDaily1
    },
    io:fwrite("Balance changed for PopugID=~0p Change=~0p~n", [PopugID, BalanceChange]),
    true = dets:insert(accounter_db, {PopugID, AccountData1}),
    EventData = #{
        version => 1,
        popug_id => PopugID,
        balance_change => BalanceChange
    },
    Event = brod_event_create(?EVENT_ACCOUNTER_BALANCE_CHANGED, EventData),
    ok = brod_event_produce(?TOPIC_ACCOUNT_BALANCE, Event),
    io:fwrite("Produced Event=~p Data=~p~n", [?EVENT_ACCOUNTER_BALANCE_CHANGED, EventData]),
    ok.
