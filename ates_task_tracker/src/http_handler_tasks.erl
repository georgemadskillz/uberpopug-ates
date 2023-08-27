-module(http_handler_tasks).

-export([init/2]).

init(Req, State) ->
    handle_method(cowboy_req:method(Req), Req, State).

handle_method(<<"POST">>, Req, State) ->
    case handle_post_request(Req) of
        ok ->
            {ok, reply_html(200, Req), State};
        {error, {match_query, {required, _Key}}} ->
            {ok, reply_html(400, Req), State};
        {error, no_body} ->
            {ok, reply_html(400, Req)};
        {error, bad_json} ->
            {ok, reply_html(400, Req)};
        {error, bad_query} ->
            {ok, reply_html(400, Req), State};
        {error, internal} ->
            {ok, reply_html(500, Req), State}
    end;
handle_method(_NotImpl, Req, State) ->
    {ok, reply_html(405, Req), State}.

handle_post_request(Req) ->
    case cowboy_req:has_body(Req) of
        true ->
            {ok, Body, _Req1} = read_body(Req, <<>>),
            case parse_body(Body) of
                {ok, JSON} ->
                    ates_task_tracker:create_task(JSON);
                Error ->
                    Error
            end;
        false ->
            {error, no_body}
    end.

read_body(Req0, Acc) ->
    case cowboy_req:read_body(Req0) of
        {ok, Data, Req} -> {ok, << Acc/binary, Data/binary >>, Req};
        {more, Data, Req} -> read_body(Req, << Acc/binary, Data/binary >>)
    end.

parse_body(Body) ->
    try
        {ok, jsx:decode(Body)}
    catch
        _ ->
            {error, bad_json}
    end.

%reply_json(Code, JSON, Req) ->
%    cowboy_req:reply(
%        Code,
%        #{<<"content-type">> => <<"application/json">>},
%        JSON,
%        Req
%    ).

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
