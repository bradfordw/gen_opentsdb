-module(gen_opentsdb).
-behaviour(gen_server).

%% API
-export([start_link/0, put_metric/2, put_metric/3, put_metric_/2, put_metric_/3, q/1]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(TCP_DEFAULT, [binary, {packet, 0}]).

-record(otsdb, {host="localhost", port=4242, tags=[{<<"source">>, <<"gen_opentsdb">>}]}).

%% API
start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

put_metric(Name, Amount) ->
  put_metric(Name, Amount, []).

put_metric(Name, Amount, Tags) ->
  gen_server:call(?MODULE, {put, Name, Amount, Tags}).

put_metric_(Name, Amount) ->
  put_metric(Name, Amount, []).

put_metric_(Name, Amount, Tags) ->
  gen_server:cast(?MODULE, {put, Name, Amount, Tags}).

%% TODO add query HTTP API here, return decoded json.
q(Cmd) ->
  {ok, Cmd}.

%% gen_server-y goodness
init([]) ->
	{ok, #otsdb{}}.

handle_call({put, Metric, Amount, Tags}, _From, State) ->
  Reply = execute(State, {put, Metric, Amount, Tags}),
  {reply, Reply, State};
handle_call(_Request, _From, State) ->
	{reply, ok, State}.

handle_cast({put, Metric, Amount, Tags}, State) ->
  execute(State, {put, Metric, Amount, Tags}),
  {noreply, State};
handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info(_Info, State) ->
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% Internal functions
unix_timestamp() ->
  calendar:datetime_to_gregorian_seconds(calendar:now_to_universal_time(now())) - 719528 * 24 * 3600.

execute(#otsdb{tags=DefTags, host=Host, port=Port}, Action) ->
  case Action of
    {put, Metric, Amount, Tags} ->
      case convert_amount(Amount) of
        {ok, SafeAmount} ->
          {ok, Sock} = gen_tcp:connect(Host, Port, ?TCP_DEFAULT),
          write(Sock, {Metric, SafeAmount, DefTags ++ Tags});
        _ -> {error, invalid_amount}
      end;
    _ -> {error, invalid_action}
  end.

write(Sock, {Metric, Amount, Tags}) ->
  SafeTags = format_tags(Tags),
  T = list_to_binary(integer_to_list(unix_timestamp())),
  Msg = <<$p,$u,$t,$\s, T/binary, $\s, Metric/binary, $\s, Amount/binary, SafeTags/binary, $\n>>,
  Reply = gen_tcp:send(Sock, Msg),
  ok = gen_tcp:close(Sock),
  Reply.

convert_amount(Amount) ->
  NewAmount = case Amount of
    A when is_integer(A) -> {ok, list_to_binary(integer_to_list(A))};
    A when is_float(A) -> {ok, list_to_binary(float_to_list(A))};
    A when is_list(A) -> {ok, list_to_binary(A)};
    A when is_binary(A) -> {ok, A};
    _ -> {error, unknown_type}
  end,
  NewAmount.

format_tags(Tags) ->
  lists:foldl(fun(E, A) ->
    <<A/binary, E/binary>>
  end, <<>>, [<<K/binary, $=, V/binary, $\s>> || {K, V} <- Tags]).
