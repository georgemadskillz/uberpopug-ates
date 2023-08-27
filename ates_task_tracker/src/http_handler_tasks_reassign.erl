-module(http_handler_tasks_reassign).

-export([init/2]).

init(Req, State) ->
    handle_method(cowboy_req:method(Req), Req, State).

handle_method(<<"POST">>, Req, State) ->
    case handle_post_request(Req) of
        ok ->
            {ok, reply_html(200, Req), State};
        {error, internal} ->
            {ok, reply_html(500, Req), State}
    end;
handle_method(_NotImpl, Req, State) ->
    {ok, reply_html(405, Req), State}.

handle_post_request(_Req) ->
    ates_task_tracker:reassign_tasks().

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
