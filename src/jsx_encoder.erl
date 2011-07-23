%% The MIT License

%% Copyright (c) 2011 Alisdair Sullivan <alisdairsullivan@yahoo.ca>

%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:

%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.

%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.


-module(jsx_encoder).


-export([encoder/1]).


-include("jsx_common.hrl").


-record(opts, {
    escaped_unicode = codepoint,
    multi_term = false,
    encoding = auto
}).


-spec encoder(Opts::jsx_opts()) -> jsx_encoder().

encoder(Opts) -> fun(Forms) -> start(Forms, Opts) end.
    

-define(ENDJSON,
    {event, end_json, fun() -> 
        {incomplete, fun(Forms) -> {error, {badjson, Forms}} end} 
    end}
).

    
start({string, String}, _Opts) when is_list(String) ->
    {event, {string, String}, fun() -> ?ENDJSON end};
start({float, Float}, _Opts) when is_list(Float) ->
    {event, {float, Float}, fun() -> ?ENDJSON end};
start({integer, Int}, _Opts) when is_list(Int) ->
    {event, {integer, Int}, fun() -> ?ENDJSON end};
start({literal, Atom}, _Opts) when Atom == true; Atom == false; Atom == null ->
    {event, {literal, Atom}, fun() -> ?ENDJSON end};
%% second parameter is a stack to match end_foos to start_foos
start(Forms, Opts) -> list_or_object(Forms, [], Opts).


list_or_object([start_object|Forms], Stack, Opts) ->
    {event, start_object, fun() -> key(Forms, [object] ++ Stack, Opts) end};
list_or_object([start_array|Forms], Stack, Opts) ->
    {event, start_array, fun() -> value(Forms, [array] ++ Stack, Opts) end};
list_or_object([], Stack, Opts) ->
    {incomplete, fun(end_stream) -> 
            {error, {badjson, []}}
        ; (Stream) -> 
            list_or_object(Stream, Stack, Opts) 
    end};
list_or_object(Forms, _, _) -> {error, {badjson, Forms}}.

 
key([{key, Key}|Forms], Stack, Opts) when is_list(Key) ->
    {event, {key, Key}, fun() -> value(Forms, Stack, Opts) end};
key([end_object|Forms], [object|Stack], Opts) ->
    {event, end_object, fun() -> maybe_done(Forms, Stack, Opts) end};
key([], Stack, Opts) ->
    {incomplete, fun(end_stream) -> 
            {error, {badjson, []}}
        ; (Stream) -> 
            key(Stream, Stack, Opts) 
    end};
key(Forms, _, _) -> {error, {badjson, Forms}}.


value([{string, S}|Forms], Stack, Opts) when is_list(S) ->
    {event, {string, S}, fun() -> maybe_done(Forms, Stack, Opts) end};
value([{float, F}|Forms],  Stack, Opts) when is_list(F) ->
    {event, {float, F}, fun() -> maybe_done(Forms, Stack, Opts) end};
value([{integer, I}|Forms], Stack, Opts) when is_list(I) ->
    {event, {integer, I}, fun() -> maybe_done(Forms, Stack, Opts) end};
value([{literal, L}|Forms], Stack, Opts)
        when L == true; L == false; L == null ->
    {event, {literal, L}, fun() -> maybe_done(Forms, Stack, Opts) end};
value([start_object|Forms], Stack, Opts) ->
    {event, start_object, fun() -> key(Forms, [object] ++ Stack, Opts) end};
value([start_array|Forms], Stack, Opts) ->
    {event, start_array, fun() -> value(Forms, [array] ++ Stack, Opts) end};
value([end_array|Forms], [array|Stack], Opts) ->
    {event, end_array, fun() -> maybe_done(Forms, Stack, Opts) end};
value([], Stack, Opts) ->
    {incomplete, fun(end_stream) -> 
            {error, {badjson, []}}
        ; (Stream) -> 
            value(Stream, Stack, Opts) 
    end};
value(Forms, _, _) -> {error, {badjson, Forms}}.


maybe_done([], [], _) -> ?ENDJSON;
maybe_done([end_json], [], _) -> ?ENDJSON;
maybe_done([end_json|Forms], [], #opts{multi_term=true}=Opts) ->
    {event, end_json, fun() -> start(Forms, Opts) end};
maybe_done([end_object|Forms], [object|Stack], Opts) ->
    {event, end_object, fun() -> maybe_done(Forms, Stack, Opts) end};
maybe_done([end_array|Forms], [array|Stack], Opts) ->
    {event, end_array, fun() -> maybe_done(Forms, Stack, Opts) end};
maybe_done(Forms, [object|_] = Stack, Opts) -> key(Forms, Stack, Opts);
maybe_done(Forms, [array|_] = Stack, Opts) -> value(Forms, Stack, Opts);
maybe_done([], Stack, Opts) ->
    {incomplete, fun(end_stream) -> 
            {error, {badjson, []}}
        ; (Stream) -> 
            maybe_done(Stream, Stack, Opts) 
    end};
maybe_done(Forms, _, _) -> {error, {badjson, Forms}}.



-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").



encode(Terms) -> encode_whole(Terms) andalso encode_incremental(Terms).


encode_whole(Terms) ->
    case loop((encoder([]))(Terms), []) of
        %% unwrap naked values
        {ok, [Terms]} -> true
        ; {ok, Terms} -> true
        ; _ -> false
    end.


encode_incremental(Terms) when is_list(Terms) ->
    encode_incremental(Terms, encoder([]), Terms, []);
%% we could feed naked terms to the regular encoder, but we already do that, so
%%  cheat instead
encode_incremental(_) -> true.

encode_incremental([Term], F, Expected, Acc) ->
    case loop(F([Term]), []) of
        {ok, R} -> Expected =:= Acc ++ R
        ; _ -> false
    end;
encode_incremental([Term|Terms], F, Expected, Acc) ->
    case loop(F([Term]), []) of
        {incomplete, Next, R} ->
            encode_incremental(Terms, Next, Expected, Acc ++ R)
        ; _ ->
            false
    end.


loop({error, _}, _) -> error;
loop({incomplete, Next}, Acc) -> {incomplete, Next, lists:reverse(Acc)};
loop({event, end_json, Next}, Acc) ->
    {incomplete, F} = Next(),
    {error, {badjson, []}} = F([]),
    {ok, lists:reverse(Acc)};
loop({event, Event, Next}, Acc) -> loop(Next(), [Event] ++ Acc).


encode_test_() ->    
    [
        {"empty object", ?_assert(encode([start_object, end_object]))},
        {"empty array", ?_assert(encode([start_array, end_array]) =:= true)},
        {"nested empty objects", ?_assert(encode([start_object,
            {key, "empty object"},
            start_object,
            {key, "empty object"},
            start_object,
            end_object,
            end_object,
            end_object
        ]))},
        {"nested empty arrays", ?_assert(encode([start_array,
            start_array,
            start_array,
            end_array,
            end_array,
            end_array
        ]))},
        {"simple object", ?_assert(encode([start_object, 
            {key, "a"},
            {string, "hello"},
            {key, "b"},
            {integer, "1"},
            {key, "c"},
            {float, "1.0"},
            {key, "d"},
            {literal, true},
            end_object
        ]))},
        {"simple array", ?_assert(encode([start_array,
            {string, "hello"},
            {integer, "1"},
            {float, "1.0"},
            {literal, true},
            end_array
        ]))},
        {"unbalanced array", ?_assertNot(encode([start_array,
            end_array,
            end_array
        ]))},
        {"naked string", ?_assert(encode({string, "hello"}))},
        {"naked literal", ?_assert(encode({literal, true}))},
        {"naked integer", ?_assert(encode({integer, "1"}))},
        {"naked float", ?_assert(encode({float, "1.0"}))}
    ].

-endif.
    