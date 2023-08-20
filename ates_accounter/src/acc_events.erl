-module(acc_events).

-export([init/0]).
-export([handle_event/1]).

-define(TOPIC_ACC_CREATE, <<"topic_account_create">>). 

init() ->
    {ok, _} = application:ensure_all_started(brod),
    KafkaBootstrapEndpoints = [{"localhost", 9092}],
    ok = brod:start_client(KafkaBootstrapEndpoints, acc_client),
    SubscriberCallbackFun =
        fun(_Partition, Msg, State) ->
            ates_accounter:handle_event(Msg),
            {ok, ack, State}
        end,
    Receive = fun() -> receive Msg -> Msg after 1000 -> timeout end end,
    brod_topic_subscriber:start_link(
        acc_client,
        ?TOPIC_ACC_CREATE,
        Partitions=[0],
        _ConsumerConfig=[{begin_offset, FirstOffset}],
        _CommittedOffsets=[], message, SubscriberCallbackFun,
        _State = #{}
    ),
    ok.

handle_event(Event) ->
    {Decoded} = jiffy:decode(Event),
    case proplists:get_value(<<"event">>, Decoded) of
        <<"AuthAccountCreated">> ->
            case proplists:get_value(<<"data">>, Decoded) of
                undefined ->
                    io:format("Error: bad event data, required 'popug_name' field~n", []),
                    {error, bad_event};
                {[{popug_name, Name}]} ->
                    create_account(Name),
                    %TODO: generate event "AccAccountCreated"
                    ok
            end
        undefined ->
            io:format("Error: bad event data, required 'event' field~n", []),
            {error, bad_event};
    end.

create_account(Name) ->
    io:fwrite("Creating account for popug Name=~0p~n", [Name]),
    true = dets:insert_new(auth_db, {Name, init_acc(Name)}),
    io:fwrite("Created account for popug Name=~0p~n", [Name, Token]),
    {ok, <<>>}.

init_acc(Name) ->
    #{
        name => Name,
        balance => 0,
        balance_daily => 0
     }.
