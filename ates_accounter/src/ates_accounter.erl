-module(ates_accounter).

-behaviour(gen_server).

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
    io:fwrite("~p<~p> Starting ates_accounter..~n", [self(), ?MODULE]),
    application:ensure_all_started(jwt),
    application:ensure_all_started(cowboy),
    io:fwrite("Cowboy started..~n", []),
    Endpoints = [
        {"/api/v1/account/", http_handler_account, []}
    ],
    Dispatch = cowboy_router:compile([{'_', Endpoints}]),
    {ok, _} = cowboy:start_clear(
        auth_http_listener,
        [{port, 14101}],
        #{env => #{dispatch => Dispatch}}
    ),
    io:fwrite("Init DB..~n", []),
    DbOpts = [
        {type, set},
        {file, "accounter_db.dat"}
    ],
    {ok, auth_db} = dets:open_file(auth_db, DbOpts),
    acc_events:init(),
    io:fwrite("ates_accounter started.~n", []),
    {ok, #{}}.

handle_call(Request, From, State) ->
    io:fwrite("~p<~p> Unhandled call Request=~p From=~p~n", [self(), ?MODULE, Request, From]),
    {noreply, State}.

handle_cast({event, Event}, State) ->
    ok = handle_event(Event),
    {noreply, State};
handle_cast(Request, State) ->
    io:fwrite("~p<~p> Unhandled cast Request=~p~n", [self(), ?MODULE, Request]),
    {noreply, State}.

handle_info(Message, State) ->
    io:fwrite("~p<~p> Unhandled info Message=~p~n", [self(), ?MODULE, Message]),
    {noreply, State}.

%% Internal functions

handle_event(Event) ->
