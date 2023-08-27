-module(ates_task_tracker).

-behaviour(gen_server).

-include_lib("brod/include/brod.hrl").

-define(KAFKA_PARTITION, 0).
-define(KAFKA_KEY, <<"key0">>).

-define(BROD_CLIENT, brod_client).

-define(TOPIC_ACCOUNT_CREATING, <<"account_creating">>).
-define(TOPIC_TASKS, <<"tasks">>).

-define(EVENT_ACCOUNTER_ACC_CREATED, <<"AccounterAccountCreated">>).
-define(EVENT_TASK_ASSIGNED, <<"TaskAssigned">>).


%% API

-export([start_link/0]).
-export([create_task/1]).
-export([reassign_tasks/0]).

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

create_task(#{description := Description}) ->
    gen_server:call(?MODULE, {create_task, Description});
create_task(_) ->
    {error, bad_json}.

reassign_tasks() ->
    gen_server:call(?MODULE, reassign_tasks).

%% Callbacks

init([]) ->
    rand:seed(),
    io:fwrite("~p<~p> Starting ates_task_tracker..~n", [self(), ?MODULE]),
    application:ensure_all_started(jwt),
    io:fwrite("jwt started..~n", []),
    application:ensure_all_started(brod),
    io:fwrite("brod started..~n", []),
    application:ensure_all_started(cowboy),
    io:fwrite("cowboy started..~n", []),
    Endpoints = [
        {"/api/v1/tasks/", http_handler_tasks, []},
        {"/api/v1/tasks/reassign", http_handler_tasks_reassign, []}
    ],
    Dispatch = cowboy_router:compile([{'_', Endpoints}]),
    {ok, _} = cowboy:start_clear(
        task_tracker_http_listener,
        [{port, 14102}],
        #{env => #{dispatch => Dispatch}}
    ),
    io:fwrite("Init DB..~n", []),
    DbOpts = [
        {type, set},
        {file, "tasks_db.dat"}
    ],
    {ok, tasks_db} = dets:open_file(tasks_db, DbOpts),
    case brod_client_init() of
        ok ->
            io:fwrite("ates_task_tracker started.~n", []),
            {ok, #{}};
        {error, Error} ->
            io:fwrite("ates_task_tracker start failed with Error=~p~n", [Error]),
            throw("Failed to start ates_task_tracker events client")
    end.

handle_call({create_task, Description}, _From, State) ->
    io:fwrite("Creating new task, searching random popug for assign..~n", []),
    Popugs = dets:foldl(
        fun({PopugID, _}, Acc) ->
            [PopugID | Acc]
        end,
        [],
        tasks_db
    ),
    RandomedPopugID = lists:nth(rand:uniform(length(Popugs)), Popugs),
    io:fwrite("Got random popug with PopugID~n", []),
    TaskID = generate_uuid(),
    TaxSeq = lists:seq(10, 20),
    Tax = lists:nth(rand:uniform(length(TaxSeq)), TaxSeq),
    FeeSeq = lists:seq(20, 40),
    Fee = lists:nth(rand:uniform(length(FeeSeq)), FeeSeq),
    Task = #{
        id => TaskID,
        description => Description,
        status => active,
        tax => Tax,
        fee => Fee
    },
    [RandomedPopugTasks] = dets:lookup(tasks_db, RandomedPopugID),
    AppendTask = [Task | RandomedPopugTasks],
    true = dets:insert_new(tasks_db, {RandomedPopugID, AppendTask}),
    io:fwrite("New task crated for PopugID=~0p TaskID=~0p Description=~0p Tax=~0p Fee=0~p~n", [RandomedPopugID, TaskID, Description, Tax, Fee]),
    EventData = #{
        version => 1,
        task_id => TaskID,
        popug_id => RandomedPopugID,
        tax => Tax
    },
    Event = brod_event_create(?EVENT_TASK_ASSIGNED, EventData),
    ok = brod_event_produce(Event),
    io:fwrite("Produced Event=~p Data=~p~n", [?EVENT_TASK_ASSIGNED, EventData]),
    {reply, ok, State};
handle_call(reassign_tasks, _From, State) ->
    io:fwrite("Reassign tasks..~n", []),
    io:fwrite("Read popug tasks list..~n", []),
    {AllPopugs, AllTasks} = dets:foldl(
        fun({PopugID, PopugTasks}, {PopugsAcc, TasksAcc}) ->
            {[PopugID | PopugsAcc], PopugTasks ++ TasksAcc}
        end,
        {[], []},
        tasks_db
    ),
    io:fwrite("Reassigning tasks..~n", []),
    AllPopugsLen = length(AllPopugs),
    NewTasksData = lists:foldl(
        fun(Task, Acc) ->
            [{lists:nth(rand:uniform(AllPopugsLen, AllPopugs)), Task} | Acc]
        end,
        [],
        AllTasks
    ),
    lists:foreach(
        fun({PopugID, #{task_id := TaskID} = Task}) ->
            TaxSeq = lists:seq(10, 20),
            Tax = lists:nth(rand:uniform(length(TaxSeq)), TaxSeq),
            FeeSeq = lists:seq(20, 40),
            Fee = lists:nth(rand:uniform(length(FeeSeq)), FeeSeq),
            Task1 = Task#{
                tax => Tax,
                fee => Fee
            },
            true = dets:insert_new(tasks_db, {PopugID, Task1}),
            io:fwrite("Task reassign: PopugID=~0p TaskID=~0p Tax=~0p Fee=0~p~n", [PopugID, TaskID, Tax, Fee]),
            EventData = #{
                version => 1,
                task_id => TaskID,
                popug_id => PopugID,
                tax => Tax
            },
            Event = brod_event_create(?EVENT_TASK_ASSIGNED, EventData),
            ok = brod_event_produce(Event),
            io:fwrite("Produced Event=~p Data=~p~n", [?EVENT_TASK_ASSIGNED, EventData])
        end,
        NewTasksData
    ),
    io:fwrite("Tasks reassigned successfully..~n", []),
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
    ok = brod:start_consumer(?BROD_CLIENT, ?TOPIC_TASKS, []),
    {ok, _ConsumerPid} = brod:subscribe(?BROD_CLIENT, self(), ?TOPIC_TASKS, ?KAFKA_PARTITION, []),
    io:fwrite("Brod consumer started successfully~n", []),
    io:fwrite("Starting brod event producer for Topic=~p~n", [?TOPIC_TASKS]),
    case brod:start_producer(?BROD_CLIENT, ?TOPIC_TASKS, [{max_retries, 5}]) of
        ok ->
            io:fwrite("Brod producer for Topic=~p started successfully.~n", [?TOPIC_TASKS]),
            ok;
        unknown_topic_or_partition ->
            io:fwrite("Brod producer start error unknown_topic_or_partition Topic=~p, retry..~n", [?TOPIC_TASKS]),
            case brod:start_producer(?BROD_CLIENT, ?TOPIC_TASKS, [{max_retries, 5}]) of
                ok ->
                    io:fwrite("Brod producer for Topic=~p started successfully.~n", [?TOPIC_TASKS]),
                    ok;
                {error, Error} ->
                    io:fwrite("Failed to start brod producer for Topic=~p Error=~p~n", [?TOPIC_TASKS, Error]),
                    {error, start_brod_producer}
            end;
        {error, Error} ->
            io:fwrite("Failed to start brod producer for Topic=~p Error=~p~n", [?TOPIC_TASKS, Error]),
            {error, start_brod_producer}
    end.

brod_event_create(Event, Data) ->
    ok = brod_event_check(Event),
    term_to_binary({Event, Data}, [compressed]).

brod_event_check(?EVENT_TASK_ASSIGNED) ->
    ok;
brod_event_check(_NotImplemented) ->
    not_impl.

brod_event_produce(EventData) ->
    ok = brod:produce_sync(
        ?BROD_CLIENT,
        ?TOPIC_TASKS,
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
    true = dets:insert(tasks_db, {PopugID, []}),
    io:fwrite("Got event of new popug account, init tasks list for popug PopugID=~0p~n", [PopugID]),
    ok.


