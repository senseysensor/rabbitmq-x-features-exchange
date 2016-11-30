%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

%% NOTE: This plugin is compltetely based on the rabbitmq topic exchange
%% what changes is the routing algorithm.
%% That means there's a lot of duplicated code. Perhaps trie creation could 
%% be extracted into its own module to prevent.

-module(rabbit_exchange_type_x_features).

-include_lib("rabbit_common/include/rabbit.hrl").
-include_lib("rabbit_common/include/rabbit_framing.hrl").
-behaviour(rabbit_exchange_type).

-export([description/0, serialise_events/0, route/2]).
-export([validate/1, validate_binding/2,
         create/2, delete/3, policy_changed/2, add_binding/3,
         remove_bindings/3, assert_args_equivalence/2]).
-export([info/1, info/2]).

-rabbit_boot_step({?MODULE,
                   [{description, "exchange type x-features"},
                    {mfa,         {rabbit_registry, register,
                                   [exchange, <<"x-features">>, ?MODULE]}},
                    {requires,    rabbit_registry},
                    {enables,     kernel_ready}]}).

-spec headers_match
        (rabbit_framing:amqp_table(), rabbit_framing:amqp_table()) ->
            boolean().

info(_X) -> [].
info(_X, _) -> [].

description() ->
    [{description, <<"AMQP x-features exchange. Much like headers but: all passed arguments should exist and match in bindings + minimum 1 header is required">>}].

serialise_events() -> false.


parse_pick_random({bool, true}) -> true;
parse_pick_random({bool, false}) -> false;
parse_pick_random(_) -> false.


route(#exchange{name = Name, arguments = _Arguments},
      #delivery{message = #basic_message{content = Content}}) ->
    Headers = case (Content#content.properties)#'P_basic'.headers of
                  undefined -> [];
                  H         -> rabbit_misc:sort_field_table(H)
              end,
%%    rabbit_router:match_bindings(Name, fun (#binding{args = Spec}) -> headers_match(Spec, Headers) end).
    PickRandom = parse_pick_random(rabbit_misc:table_lookup(_Arguments, <<"pick_random">>)),
%%    file:write_file('/tmp/foo', io_lib:fwrite("_Arguments: ~p; parsed value: ~p\n-------------------\n\n", [_Arguments, PickRandom]), [append]),
    Matches = rabbit_router:match_bindings(Name, fun (#binding{args = Spec}) -> headers_match(Spec, Headers) end),
    if
      PickRandom == true ->
        case length(Matches) of
          Len when Len < 2 -> Matches;
          Len ->
            Rand = crypto:rand_uniform(1, Len + 1),
            [lists:nth(Rand, Matches)]
        end;
      true -> Matches
    end.

validate_binding(_X, _Bindings) -> ok.


%% Horrendous matching algorithm. Depends for its merge-like
%% (linear-time) behaviour on the lists:keysort
%% (rabbit_misc:sort_field_table) that route/1 and
%% rabbit_binding:{add,remove}/2 do.
%%
%%                 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
%% In other words: REQUIRES BOTH PATTERN AND DATA TO BE SORTED ASCENDING BY KEY.
%%                 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
%%
headers_match(Args, Data) ->
%%    MK = parse_x_match(rabbit_misc:table_lookup(Args, <<"x-match">>)),
%%    headers_match(Args, Data, true, false, all).
    if
      length(Data) > 0 -> headers_match(Args, Data, true, false, all);
      length(Data) =< 0 -> false
    end.

% A bit less horrendous algorithm :)
headers_match(_, _, false, _, all) ->
%%  file:write_file('/tmp/foo', "Total false\n\n", [append]),
  false;
%%headers_match(_, _, _, true, any) -> true;


headers_match([], [], AllMatch, _AnyMatch, all) ->
%%  file:write_file('/tmp/foo', "[], []\n\n", [append]),
  AllMatch;

% Delete headers starting with x-
headers_match(Args, [{<<"x-", _/binary>>, _DT, _DV} | DRest],
              AllMatch, AnyMatch, MatchKind) ->
%%    file:write_file('/tmp/foo', "Extract HEADER x-\n\n", [append]),
    headers_match(Args, DRest, AllMatch, AnyMatch, MatchKind);

% No more bindings, return false for all
headers_match([], _Data, _AllMatch, _AnyMatch, all) ->
%%  file:write_file('/tmp/foo', io_lib:fwrite("[], Data. Resolution: ~p, return false anyway. (Data: ~p)\n", [_AllMatch, _Data]), [append]),
  false;

% No more headers, return current state
headers_match(_, [], AllMatch, _AnyMatch, all) ->
%%  file:write_file('/tmp/foo', "_, []\n\n", [append]),
  AllMatch;

%%headers_match([], _Data, _AllMatch, AnyMatch, any) -> AnyMatch;

% Delete bindings starting with x-
headers_match([{<<"x-", _/binary>>, _PT, _PV} | PRest], Data,
              AllMatch, AnyMatch, MatchKind) ->
%%    file:write_file('/tmp/foo', "Extract x-\n\n", [append]),
    headers_match(PRest, Data, AllMatch, AnyMatch, MatchKind);

% No more data, but still bindings, going on
headers_match(_Pattern, [], AllMatch, AnyMatch, MatchKind) ->
%%    file:write_file('/tmp/foo', io_lib:fwrite("No more data, but still bindings, going on. Pattern: ~p\n-------------------\n\n", [_Pattern]), [append]),
    headers_match([], [], AllMatch, AnyMatch, MatchKind);

% Data key header not in binding, go next data
% (Required feature is unavailable in binding! should return false)
headers_match(Pattern = [{PK, _PT, _PV} | _], [{DK, _DT, _DV} | DRest],
              _AllMatch, AnyMatch, MatchKind) when PK > DK ->
%%    file:write_file('/tmp/foo', io_lib:fwrite("Data key header not in binding, go next data. PK: ~p; DK: ~p; PV: ~p; DV: ~p\n-------------------\n\n", [PK, DK, _PV, _DV]), [append]),
    headers_match(Pattern, DRest, false, AnyMatch, MatchKind);

% Binding key header not in data, false with all, go next binding
% (Some feature in binding which was not requested by header. Should go on)
headers_match([{PK, _PT, _PV} | PRest], Data = [{DK, _DT, _DV} | _],
              AllMatch, AnyMatch, MatchKind) when PK < DK ->
%%    file:write_file('/tmp/foo', io_lib:fwrite("Binding key header not in data, false with all, go next binding. PK: ~p; DK: ~p; PV: ~p; DV: ~p\n-------------------\n\n", [PK, DK, _PV, _DV]), [append]),
    headers_match(PRest, Data, AllMatch, AnyMatch, MatchKind);

%% It's not properly specified, but a "no value" in a
%% pattern field is supposed to mean simple presence of
%% the corresponding data field. I've interpreted that to
%% mean a type of "void" for the pattern field.
headers_match([{PK, void, _PV} | PRest], [{DK, _DT, _DV} | DRest],
              AllMatch, _AnyMatch, MatchKind) when PK == DK ->
%%    file:write_file('/tmp/foo', io_lib:fwrite("Void case. PK: ~p; DK: ~p; PV: ~p; DV: ~p\n-------------------\n\n", [PK, DK, _PV, _DV]), [append]),
    headers_match(PRest, DRest, AllMatch, true, MatchKind);

% Complete match, true with any, go next
headers_match([{PK, _PT, PV} | PRest], [{DK, _DT, DV} | DRest],
              AllMatch, _AnyMatch, MatchKind) when PK == DK andalso PV == DV ->
%%    file:write_file('/tmp/foo', io_lib:fwrite("Complete match, true with any, go next. PK: ~p; DK: ~p; PV: ~p; DV: ~p\n-------------------\n\n", [PK, DK, PV, DV]), [append]),
    headers_match(PRest, DRest, AllMatch, true, MatchKind);

% Value does not match, false with all, go next
headers_match([{PK, _PT, _PV} | PRest], [{DK, _DT, _DV} | DRest],
              _AllMatch, AnyMatch, MatchKind) when PK == DK ->
%%  file:write_file('/tmp/foo', io_lib:fwrite("Value does not match, false with all, go next. PK: ~p; DK: ~p; PV: ~p; DV: ~p\n-------------------\n\n", [PK, DK, _PV, _DV]), [append]),
  headers_match(PRest, DRest, false, AnyMatch, MatchKind).


validate(_X) -> ok.
create(_Tx, _X) -> ok.
delete(_Tx, _X, _Bs) -> ok.
policy_changed(_X1, _X2) -> ok.
add_binding(_Tx, _X, _B) -> ok.
remove_bindings(_Tx, _X, _Bs) -> ok.
assert_args_equivalence(X, Args) ->
    rabbit_exchange:assert_args_equivalence(X, Args).
