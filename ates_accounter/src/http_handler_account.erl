-module(http_handler_account).

-export([init/2]).

-export([constraint_popug_name/2]).
-export([constraint_popug_pass/2]).

init(Req, State) ->
    handle_method(cowboy_req:method(Req), Req, State).

handle_method(<<"POST">>, Req, State) ->
    case handle_request(Req) of
        {ok, JSON} ->
            {ok, reply_json(200, JSON, Req), State};
        {error, {match_query, {required, _Key}}} ->
            {ok, reply_html(400, Req), State};
        {error, bad_query} ->
            {ok, reply_html(400, Req), State};
        {error, internal} ->
            {ok, reply_html(500, Req), State}
    end;
handle_method(_NotImpl, Req, State) ->
    {ok, reply_html(405, Req), State}.

handle_request(Req) ->
    case parse_query(Req) of
        {ok, Params} ->
            case ates_auth:create_account(Params) of
                ok ->
                 {ok, <<>>};
                Error ->
                    Error
            end;
        Error ->
            Error
    end.

parse_query(Req) ->
    Constraints = [
        {popug_name, fun constraint_popug_name/2, undefined},
        {popug_pass, fun constraint_popug_pass/2, undefined}
    ],
    match_query(Constraints, Req).

constraint_popug_name(forward, <<>>) ->
    error;
constraint_popug_name(forward, Val) when is_binary(Val) ->
    {ok, Val};
constraint_popug_name(forward, _Val) ->
    error.

constraint_popug_pass(forward, <<>>) ->
    error;
constraint_popug_pass(forward, Val) when is_binary(Val) ->
    {ok, Val};
constraint_popug_pass(forward, _Val) ->
    error.

match_query(Constraints, Req) ->
    try
        Matched = cowboy_req:match_qs(Constraints, Req),
        {ok, Matched}
    catch
        % Required key not found in query
        error:{badkey, K} ->
            io:fwrite("Required Key=~0p not found in query~n", [K]),
            {error, {match_query, {required, K}}};
        % Constraints failed
        exit:{request_error, {match_qs, Errors}, _} ->
            io:fwrite("Query params match faield Error=~0p~n", [Errors]),
            {error, match_query};
        % Bad query
        exit:{request_error, qs, Error} ->
            io:fwrite("Bad query params Error=~0p~n", [Error]),
            {error, bad_query};
        % Unknown
        _:X ->
            io:fwrite("Bad query params Error=~0p~n", [X]),
            {error, bad_query}
    end.

reply_json(Code, JSON, Req) ->
    cowboy_req:reply(
        Code,
        #{<<"content-type">> => <<"application/json">>},
        JSON,
        Req
    ).

reply_html(Code, Req) ->
    reply_html(Code, lib_http:http_code_body(Code), Req).

reply_html(Code, Text, Req) ->
    cowboy_req:reply(
        Code,
        #{
            <<"content-type">> => <<"text/html">>
        },
        Text,
        Req
    ).
