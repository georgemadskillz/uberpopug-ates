-module(auth_events).

-export([init/0]).
-export([produce/1]).

-define(TOPIC_ACC_CREATE, <<"topic_account_create">>).

init() ->
    {ok, _} = application:ensure_all_started(brod),
    KafkaBootstrapEndpoints = [{"localhost", 9092}],
    ok = brod:start_client(KafkaBootstrapEndpoints, auth_client),
    ok = brod:start_producer(auth_client, ?TOPIC_ACC_CREATE, _ProducerConfig = []),
    ok.

produce(EventData) ->
    Partition = 0,
    ok = brod:produce_sync(auth_client, ?TOPIC_ACC_CREATE, Partition, <<"key0">>, EventData),
    ok.
