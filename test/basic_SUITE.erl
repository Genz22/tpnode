-module(basic_SUITE).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").


-define(TESTNET_NODES, [
  "test_c4n1",
  "test_c4n2",
  "test_c4n3",
  "test_c5n1",
  "test_c5n2",
  "test_c5n3",
  "test_c6n1",
  "test_c6n2",
  "test_c6n3"
]).

%%-define(TESTNET_NODES, [
%%    "test_c4n1",
%%    "test_c4n2",
%%    "test_c4n3"
%%]).

all() ->
    [
        discovery_got_announce_test,
        discovery_register_test,
        discovery_lookup_test,
        discovery_unregister_by_name_test,
        discovery_unregister_by_pid_test,
        discovery_ssl_test,
        transaction_test,
        register_wallet_test,
        smartcontract_test,
        check_blocks_test
        %,crashme_test
        %instant_sync_test
    ].

% -----------------------------------------------------------------------------

init_per_suite(Config) ->
%%    Env = os:getenv(),
%%    io:fwrite("env ~p", [Env]),
%%    io:fwrite("w ~p", [os:cmd("which erl")]),
    file:make_symlink("../../../../db", "db"),
    application:ensure_all_started(inets),
    ok = wait_for_testnet(60),
    %cover_start(),
%%    Config ++ [{processes, Pids}].
    Config.

% -----------------------------------------------------------------------------

init_per_testcase(_, Config) ->
    Config.

% -----------------------------------------------------------------------------

end_per_testcase(_, Config) ->
    Config.

% -----------------------------------------------------------------------------

end_per_suite(Config) ->
%%    Pids = proplists:get_value(processes, Config, []),
%%    lists:foreach(
%%        fun(Pid) ->
%%            io:fwrite("Killing ~p~n", [Pid]),
%%            exec:kill(Pid, 15)
%%        end, Pids),
    %cover_finish(),
    save_bckups(),
    Config.

% -----------------------------------------------------------------------------

save_bckups() ->
    logger("saving bckups"),
    SaveBckupForNode =
        fun(Node) ->
            BckupDir = "/tmp/ledger_bckups/" ++ Node ++ "/",
%%        filelib:ensure_dir("../../../../" ++ BckupDir),
            filelib:ensure_dir(BckupDir),
            logger("saving bckup for node ~p to dir ~p", [Node, BckupDir]),
            rpc:call(get_node(Node), blockchain_updater, backup, [BckupDir])
        end,
    lists:foreach(SaveBckupForNode, get_testnet_nodenames()),
    ok.
  


%%get_node_cmd(Name) when is_list(Name) ->
%%    "erl -progname erl -config " ++ Name ++ ".config -sname "++ Name ++ " -detached -noshell -pa _build/default/lib/*/ebin +SDcpu 2:2: -s lager -s tpnode".
%%%%    "sleep 1000".

%%run_testnet_nodes() ->
%%    exec:start([]),
%%
%%    io:fwrite("my name: ~p", [erlang:node()]),
%%
%%    Pids = lists:foldl(
%%        fun(NodeName, StartedPids) ->
%%            Cmd = get_node_cmd(NodeName),
%%            {ok, _Pid, OsPid} = exec:run_link(Cmd, []),
%%
%%            io:fwrite("Started node ~p with os pid ~p", [NodeName, OsPid]),
%%            [OsPid | StartedPids]
%%        end, [], get_testnet_nodenames()
%%    ),
%%    ok = wait_for_testnet(Pids),
%%    {ok, Pids}.

cover_start() ->
    application:load(tpnode),
    {true,{appl,tpnode,{appl_data,tpnode,_,_,_,Modules,_,_,_},_,_,_,_,_,_}}=application_controller:get_loaded(tpnode),
    cover:compile_beam(Modules),
    lists:map(
        fun(NodeName) ->
            rpc:call(NodeName,cover,compile_beam,[Modules])
        end, nodes()),
    ct_cover:add_nodes(nodes()),
    cover:start(nodes()).

% -----------------------------------------------------------------------------

cover_finish() ->
    logger("going to flush coverage data~n"),
    logger("nodes: ~p~n", [nodes()]),
    erlang:register(ctester, self()),
    ct_cover:remove_nodes(nodes()),
%%    cover:stop(nodes()),
%%    cover:stop(),
    cover:flush(nodes()),
    cover:analyse_to_file([{outdir,"cover1"}]).
%%    timer:sleep(1000).
%%    cover:analyse_to_file([{outdir,"cover"},html]).

% -----------------------------------------------------------------------------

get_node(Name) ->
    NameBin = utils:make_binary(Name),
    [_,NodeHost]=binary:split(atom_to_binary(erlang:node(),utf8),<<"@">>),
    binary_to_atom(<<NameBin/binary, "@", NodeHost/binary>>, utf8).

% -----------------------------------------------------------------------------

wait_for_testnet(Trys) ->
    AllNodes = get_testnet_nodenames(),
    NodesCount = length(AllNodes),
    Alive = lists:foldl(
        fun(Name, ReadyNodes) ->
            NodeName = get_node(Name),
            case net_adm:ping(NodeName) of
                pong ->
                    ReadyNodes + 1;
                _Answer ->
                    io:fwrite("Node ~p answered ~p~n", [NodeName, _Answer]),
                    ReadyNodes
            end
        end, 0, AllNodes),

    if
        Trys<1 ->
            timeout;
        Alive =/= NodesCount ->
            io:fwrite("testnet starting timeout: alive ~p, need ~p", [Alive, NodesCount]),
            timer:sleep(1000),
            wait_for_testnet(Trys-1);
        true -> ok
    end.

% -----------------------------------------------------------------------------

discovery_register_test(_Config) ->
    DiscoveryPid =
      rpc:call(get_node(get_default_nodename()), erlang, whereis, [discovery]),
    Answer = gen_server:call(DiscoveryPid, {register, <<"test_service">>, self()}),
    ?assertEqual(ok, Answer).


discovery_lookup_test(_Config) ->
    DiscoveryPid =
      rpc:call(get_node(get_default_nodename()), erlang, whereis, [discovery]),
    gen_server:call(DiscoveryPid, {register, <<"test_service">>, self()}),
    Result1 = gen_server:call(DiscoveryPid, {get_pid, <<"test_service">>}),
    ?assertMatch({ok, _, <<"test_service">>}, Result1),
    Result2 = gen_server:call(DiscoveryPid, {lookup, <<"nonexist">>}),
    ?assertEqual([], Result2),
    Result3 = gen_server:call(DiscoveryPid, {lookup, <<"tpicpeer">>}),
    ?assertNotEqual(0, length(Result3)).


discovery_unregister_by_name_test(_Config) ->
    DiscoveryPid =
      rpc:call(get_node(get_default_nodename()), erlang, whereis, [discovery]),
    gen_server:call(DiscoveryPid, {register, <<"test_service">>, self()}),
    gen_server:call(DiscoveryPid, {register, <<"test_service2">>, self()}),
    Result1 = gen_server:call(DiscoveryPid, {get_pid, <<"test_service">>}),
    ?assertEqual({ok, self(), <<"test_service">>}, Result1),
    gen_server:call(DiscoveryPid, {unregister, <<"test_service">>}),
    Result2 = gen_server:call(DiscoveryPid, {get_pid, <<"test_service">>}),
    ?assertEqual({error,not_found,<<"test_service">>}, Result2),
    Result3 = gen_server:call(DiscoveryPid, {get_pid, <<"test_service2">>}),
    ?assertEqual({ok, self(), <<"test_service2">>}, Result3).


discovery_unregister_by_pid_test(_Config) ->
    DiscoveryPid =
      rpc:call(get_node(get_default_nodename()), erlang, whereis, [discovery]),
    MyPid = self(),
    gen_server:call(DiscoveryPid, {register, <<"test_service">>, MyPid}),
    gen_server:call(DiscoveryPid, {register, <<"test_service2">>, MyPid}),
    Result1 = gen_server:call(DiscoveryPid, {get_pid, <<"test_service">>}),
    ?assertEqual({ok, MyPid, <<"test_service">>}, Result1),
    Result2 = gen_server:call(DiscoveryPid, {get_pid, <<"test_service2">>}),
    ?assertEqual({ok, MyPid, <<"test_service2">>}, Result2),
    gen_server:call(DiscoveryPid, {unregister, MyPid}),
    Result3 = gen_server:call(DiscoveryPid, {get_pid, <<"test_service">>}),
    ?assertEqual({error, not_found, <<"test_service">>}, Result3),
    Result4 = gen_server:call(DiscoveryPid, {get_pid, <<"test_service2">>}),
    ?assertEqual({error, not_found, <<"test_service2">>}, Result4).


build_announce(Name) when is_binary(Name)->
  build_announce(#{name => Name});

% build announce as c4n3
build_announce(Options) when is_map(Options) ->
  Now = os:system_time(second),
  Name = maps:get(name, Options, <<"service_name">>),
  Proto =  maps:get(proto, Options, api),
  Port = maps:get(port, Options, 1234),
  Hostname = utils:make_list(maps:get(hostname, Options, "c4n3.pwr.local")),
  Scopes = maps:get(scopes, Options, [api, xchain]),
  Ttl = maps:get(ttl, Options, 600),
  Created = maps:get(created, Options, Now),
  Chain = maps:get(chain, Options, 4),
  Ip = utils:make_binary(maps:get(ip, Options, <<"127.0.0.1">>)),
  Announce = #{
    name => Name,
    address => #{
      address => Ip,
      hostname => Hostname,
      port => Port,
      proto => Proto
    },
    created => Created,
    ttl => Ttl,
    scopes => Scopes,
    nodeid => <<"28AFpshz4W4YD7tbLj1iu4ytpPzQ">>, % id from c4n3
    chain => Chain
  },
  meck:new(nodekey),
  % priv key from c4n3 node
  meck:expect(nodekey, get_priv, fun() ->
    hex:parse("2ACC7ACDBFFA92C252ADC21D8469CC08013EBE74924AB9FEA8627AE512B0A1E0") end),
  AnnounceBin = discovery:pack(Announce),
  meck:unload(nodekey),
  {Announce, AnnounceBin}.

discovery_ssl_test(_Config) ->
  DiscoveryC4N1 = rpc:call(get_node(get_default_nodename()), erlang, whereis, [discovery]),
  ServiceName = <<"apispeer">>,
  {Announce, AnnounceBin} =
    build_announce(#{
      name => ServiceName,
      proto => apis
    }),
  NodeId = maps:get(nodeid, Announce, unknown),
  Address = maps:get(address, Announce, unknown),
  Hostname = utils:make_binary(maps:get(hostname, Address, unknown)),
  IpAddr = utils:make_binary(maps:get(address, Address, unknown)),
  PortNo = maps:get(port, Address, 1234),
  Host = <<"https://", Hostname/binary, ":", (integer_to_binary(PortNo))/binary>>,
  Ip =  <<"https://", IpAddr/binary, ":", (integer_to_binary(PortNo))/binary>>,
  gen_server:cast(DiscoveryC4N1, {got_announce, AnnounceBin}),
  timer:sleep(2000),  % wait for announce propagation
  Result = rpc:call(get_node(get_default_nodename()), tpnode_httpapi, get_nodes, [4]),
  logger("get_nodes answer: ~p~n", [Result]),
  ?assertMatch(#{NodeId := #{ host := _, ip := _}}, Result),
  AddrInfo = maps:get(NodeId, Result, #{}),
  Hosts = maps:get(host, AddrInfo, []),
  Ips = maps:get(ip, AddrInfo, []),
  ?assertEqual(true, lists:member(Host, Hosts)),
  ?assertEqual(true, lists:member(Ip, Ips)).
  
  


discovery_got_announce_test(_Config) ->
    DiscoveryC4N1 = rpc:call(get_node(<<"test_c4n1">>), erlang, whereis, [discovery]),
    DiscoveryC4N2 = rpc:call(get_node(<<"test_c4n2">>), erlang, whereis, [discovery]),
    DiscoveryC4N3 = rpc:call(get_node(<<"test_c4n3">>), erlang, whereis, [discovery]),
    DiscoveryC5N2 = rpc:call(get_node(<<"test_c5n2">>), erlang, whereis, [discovery]),
    Rnd = integer_to_binary(rand:uniform(100000)),
    ServiceName = <<"looking_glass_", Rnd/binary>>,
    {Announce, AnnounceBin} = build_announce(ServiceName),
    gen_server:cast(DiscoveryC4N1, {got_announce, AnnounceBin}),
    timer:sleep(2000),  % wait for announce propagation
    Result = gen_server:call(DiscoveryC4N1, {lookup, ServiceName, 4}),
    NodeId = maps:get(nodeid, Announce, <<"">>),
    Address = maps:get(address, Announce),
    Experted = [
        maps:put(nodeid, NodeId, Address)
    ],
    ?assertEqual(Experted, Result),
    % c4n1 should forward the announce to c4n2
    Result1 = gen_server:call(DiscoveryC4N2, {lookup, ServiceName, 4}),
    ?assertEqual(Experted, Result1),
    Result2 = gen_server:call(DiscoveryC4N2, {lookup, ServiceName, 5}),
    ?assertEqual([], Result2),
    % c4n3 should discard self announce
    Result3 = gen_server:call(DiscoveryC4N3, {lookup, ServiceName, 4}),
    ?assertEqual([], Result3),
    % c5n2 should get info from xchain announce
    Result4 = gen_server:call(DiscoveryC5N2, {lookup, ServiceName, 4}),
    ?assertEqual(Experted, Result4),
    Result5 = gen_server:call(DiscoveryC5N2, {lookup, ServiceName, 5}),
    ?assertEqual([], Result5).

api_get_tx_status(TxId) ->
    api_get_tx_status(TxId, get_base_url()).

api_get_tx_status(TxId, BaseUrl) ->
    Status = tpapi:get_tx_status(TxId, BaseUrl),
    case Status of
      {ok, timeout, _} ->
        logger("got transaction ~p timeout~n", [TxId]),
        dump_testnet_state();
      {ok, #{<<"res">> := <<"ok">>}, _} ->
        logger("got transaction ~p res=ok~n", [TxId]),
        dump_testnet_state();
      {ok, #{<<"res">> := <<"bad_seq">>}, _} ->
        logger("got transaction ~p badseq~n", [TxId]),
        dump_testnet_state();
      _ ->
        ok
    end,
    Status.


%% wait for transaction commit using distribution
wait_for_tx(TxId, NodeName) ->
    wait_for_tx(TxId, NodeName, 30).

wait_for_tx(_TxId, _NodeName, 0 = _TrysLeft) ->
    dump_testnet_state(),
    {timeout, _TrysLeft};

wait_for_tx(TxId, NodeName, TrysLeft) ->
    Status = rpc:call(NodeName, txstatus, get, [TxId]),
    logger("got tx status: ~p ~n", [Status]),
    case Status of
        undefined ->
            timer:sleep(1000),
            wait_for_tx(TxId, NodeName, TrysLeft - 1);
        {true, ok} ->
            logger("transaction ~p commited~n", [TxId]),
            {ok, TrysLeft};
        {false, Error} ->
            dump_testnet_state(),
            {error, Error}
    end.


get_wallet_priv_key() ->
    address:parsekey(<<"5KHwT1rGjWiNzoZeFuDT85tZ6KTTZThd4xPfaKWRUKNqvGQQtqK">>).

get_register_wallet_transaction() ->
    PrivKey = get_wallet_priv_key(),
    tpapi:get_register_wallet_transaction(PrivKey, #{promo => <<"TEST5">>}).

register_wallet_test(_Config) ->
    RegisterTx = get_register_wallet_transaction(),
    Res = api_post_transaction(RegisterTx),
    ?assertEqual(<<"ok">>, maps:get(<<"result">>, Res, unknown)),
    TxId = maps:get(<<"txid">>, Res, unknown),
    ?assertNotEqual(unknown, TxId),
    logger("got txid: ~p~n", [TxId]),
    ?assertMatch(#{<<"result">> := <<"ok">>}, Res),
    {ok, Status, _TrysLeft} = api_get_tx_status(TxId),
    logger("transaction status: ~p ~n trys left: ~p", [Status, _TrysLeft]),
    ?assertNotEqual(timeout, Status),
    ?assertMatch(#{<<"ok">> := true}, Status),
    Wallet = maps:get(<<"res">>, Status, unknown),
    ?assertNotEqual(unknown, Wallet),
    % chech wallet status via API
    Res2 = api_get_wallet(Wallet),
    logger("Info for wallet ~p: ~p", [Wallet, Res2]),
    ?assertMatch(#{<<"result">> := <<"ok">>, <<"txtaddress">> := Wallet}, Res2),
    WalletInfo = maps:get(<<"info">>, Res2, unknown),
    ?assertNotEqual(unknown, WalletInfo),
    PubKeyFromAPI = maps:get(<<"pubkey">>, WalletInfo, unknown),
    ?assertNotEqual(unknown, PubKeyFromAPI).

% base url for c4n1 rpc
get_base_url() ->
  DefaultUrl = "http://pwr.local:49841",
  os:getenv("API_BASE_URL", DefaultUrl).


% get info for wallet
api_get_wallet(Wallet) ->
    tpapi:get_wallet_info(Wallet, get_base_url()).

% post encoded and signed transaction using API
api_post_transaction(Transaction) ->
    api_post_transaction(Transaction, get_base_url()).

api_post_transaction(Transaction, Url) ->
    tpapi:commit_transaction(Transaction, Url).

% post transaction using distribution
dist_post_transaction(Node, Transaction) ->
    rpc:call(Node, txpool, new_tx, [Transaction]).

% register new wallet using API
api_register_wallet() ->
    RegisterTx = get_register_wallet_transaction(),
    Res = api_post_transaction(RegisterTx),
    ?assertEqual(<<"ok">>, maps:get(<<"result">>, Res, unknown)),
    TxId = maps:get(<<"txid">>, Res, unknown),
    ?assertMatch(#{<<"result">> := <<"ok">>}, Res),
    {ok, Status, _} = api_get_tx_status(TxId),
    logger("register wallet transaction status: ~p ~n", [Status]),
    ?assertMatch(#{<<"ok">> := true}, Status),
    Wallet = maps:get(<<"res">>, Status, unknown),
    ?assertNotEqual(unknown, Wallet),
    logger("new wallet has been registered: ~p ~n", [Wallet]),
    Wallet.


% get current sequence for wallet
get_sequence(Node, Wallet) ->
    Ledger = rpc:call(Node, mledger, get, [naddress:decode(Wallet)]),
    case bal:get(seq, Ledger) of
        Seq when is_integer(Seq) ->
          logger(
            "node ledger seq for wallet ~p (via rpc:call): ~p~n",
            [Wallet, Seq]
          ),
          NewSeq = max(Seq, os:system_time(millisecond)),
          logger("new wallet [~p] seq chosen: ~p~n", [Wallet, NewSeq]),
          NewSeq;
        _ ->
          logger("new wallet [~p] seq chosen: 0~n", [Wallet]),
          0
    end.


make_transaction(From, To, Currency, Amount, Message) ->
    Node = get_node(get_default_nodename()),
    make_transaction(Node, From, To, Currency, Amount, Message).

make_transaction(Node, From, To, Currency, Amount, Message) ->
    Seq = get_sequence(Node, From),
    logger("seq for wallet ~p is ~p ~n", [From, Seq]),
    Tx = #{
        amount => Amount,
        cur => Currency,
        extradata =>jsx:encode(#{message=>Message}),
        from => naddress:decode(From),
        to => naddress:decode(To),
        seq=> Seq + 1,
        timestamp => os:system_time(millisecond)
    },
    logger("transaction body ~p ~n", [Tx]),
    SignedTx = tx:sign(Tx, get_wallet_priv_key()),
    Res4 = api_post_transaction(SignedTx),
    maps:get(<<"txid">>, Res4, unknown).

new_wallet() ->
  PrivKey = get_wallet_priv_key(),
  PubKey = tpecdsa:calc_pub(PrivKey, true),
  case tpapi:register_wallet(PrivKey, get_base_url()) of
    {error, timeout, TxId} ->
      logger(
        "wallet registration timeout, txid: ~p, pub key: ~p~n",
        [TxId, PubKey]
      ),
      dump_testnet_state(),
      throw(wallet_registration_timeout);
    {ok, Wallet, _TxId} ->
      Wallet;
    Other ->
      logger("wallet registration error: ~p, pub key: ~p ~n", [Other, PubKey]),
      dump_testnet_state(),
      throw(wallet_registration_error)
  end.

% -----------------------------------------------------------------------------

dump_node_state(Parent, NodeName) ->
  States =
    [
      {Module, rpc:call(get_node(NodeName), Module, get_state, [])} ||
      Module <- [blockvote, txpool, txqueue, txstorage]
    ] ++
    [{lastblock, rpc:call(get_node(NodeName), blockchain, last, [])}],
  Parent ! {states, NodeName, States}.

% -----------------------------------------------------------------------------

dump_testnet_state() ->
  logger("dump testnet state ~n"),

  Pids = [
    erlang:spawn(?MODULE, dump_node_state, [self(), NodeName]) ||
    NodeName <- get_testnet_nodenames()
  ],
  
  wait_for_dumpers(Pids),
  ok.
% -----------------------------------------------------------------------------

get_testnet_nodenames() ->
  ?TESTNET_NODES.

% -----------------------------------------------------------------------------

get_default_nodename() ->
  <<"test_c4n1">>.

% -----------------------------------------------------------------------------

wait_for_dumpers(Pids) ->
  wait_for_dumpers(Pids, #{}).


wait_for_dumpers(Pids, StatesAcc) ->
  receive
    {states, NodeName, States} ->
      wait_for_dumpers(Pids, maps:put(NodeName, States, StatesAcc))
  after 500 ->
    case lists:member(true, [is_process_alive(Pid) || Pid <- Pids]) of
      true ->
        wait_for_dumpers(Pids, StatesAcc);
      _ ->
        logger("------ testnet states data ------"),
        
        maps:filter(
          fun
            (NodeName, NodeStates) ->
              [
                logger("~p state of node ~p:~n~p~n", [Module, NodeName, State]) ||
                {Module, State} <- NodeStates
              ],
              false
          end,
          StatesAcc
        ),
        
        logger("------ end of data ------"),
        ok
    end
  end.
% -----------------------------------------------------------------------------

smartcontract_test(_Config) ->
  {ok,Addr}=application:get_env(tptest,endless_addr),
  {ok,Priv}=application:get_env(tptest,endless_addr_pk),
  ?assertMatch(true, is_binary(Addr)),
  ?assertMatch(true, is_binary(Priv)),

  %spawn erltest VMs
  _Pids=[ vm_erltest:run("127.0.0.1",P) || P<- [29841,29842,29843] ],
  timer:sleep(1000),

  %{ok, Code}=file:read_file("../examples/testcontract_emit.ec"),
  Code=zlib:uncompress(base64:decode("eJzlVn+PozYQ/Z9PYRGtDu6cDZCQZCkgnSqlqq49nS5RVWmFIgecLF1ic2A2iaLsZ78xPwKXbbfttqee1FW8Nvb4zfObAc/VFeq/7qP8wATZO4hmCWEbOaUoMXfWPNsSoakfMvpAI7TO+Bbl4SNTddxd/pkShkS8pSjO0WMK6/hWzi1gKgDTI7/Hc0EEPSEPbfNNSsJ7p2Cy07YkzZ0NFZrrqrm0UX0fo59otKEZdl3Tmvq+DhjKx4J564IpCGkRTRN+wGrMYgGufoTuF5IEGC0Xex3t7igDIsuYCQogWr2so74PmxGSbJCa0bxIYDfqHV3X8H3k+ch1a1tnPBqs4o3vnzD6geQY3Qan7556XtYe/wKwcQHZN5+C0n1KWR4/0H+IbMDfE/TlJaa4y/hOe0WzjGev9NJ0QxnN4lAeLwRdn9G0q6frzlsOXieeQLEKO4RPGs5Nb268ga34Tw81N5/R60wzol+NZv+lNLvSn4l2IvvN0W0Jt3wZF/H6cCbbO8o33/Fmp+c5v6e7xd7rHR9o5vkWvo9Z5PkVFpYInj+rSEL2eb7RjHP6qfOUkkPCCWy8DZqpCgJmjuqdEKkzGJjGtWXXbWQMBM3FgLIo5UBLhc+GmpZfLIy2NIJexfKlHlr12YMS91TBv1/82sq74tEBi70TcpaLrAjFUuy18lh6I7fxXDD+WP25cf6WgMcLvVckeqnkwB4iaw4NbI5NbBoTbA1haMEQHs0pNkc2tDG2zAkewpIxgulx3SxsT/FoIn/2EI9uMBjCfxjbEzmWA7scgMFIGtsmHk2b3wTghrUnCSf7G2hGPQeubmDewpOajzGtGlgOrdq4NiyXDKAIkn49pem2vDL+hbxuIL9IbMHb4Tmnu/ndZnfvmBZZynMKUJIs2fKCwSa7eiXDAnxBIs8WC1WmbLU9JEni+cC7YKGIOfP887tKsk0OsLZpBadvLb8jmpDDb3z1XyoPOi1XFEoWKulqTX2CovgByc+gjt6g8f8wSm2YnpQIf/NmN19+ryvw8YYa752M79mPjDZGwAcrvaMUDjkeeosbVeXT7NSaS9WluXRZWoNHuEPO5vAIibgmktZJVpRXnRK2Kjib4rXE3MXijhdCu4X4hjwqC9NOkRrgao8efFkML/a/j1IGNY83AYYTXez5Hqijx1x7TPVy5wy/vbAAqRpYGMrFLvsPcdSs5jRZayW+cnURCSDP6G7ZVtndguVa+UhzD4ps7V0p+wyD1JX4XR5hwxRSqGyp7tWe5SUMGSsyEgpcgsAxMKBKMtBdK8pnhrKVtQ==")),

  DeployTx=tx:pack(
             tx:sign(
             tx:construct_tx(
               #{ver=>2,
                 kind=>deploy,
                 from=>Addr,
                 seq=>os:system_time(millisecond),
                 t=>os:system_time(millisecond),
                 payload=>[#{purpose=>gas, amount=>50000, cur=><<"FTT">>}],
                 call=>#{function=>"init",args=>[1024]},
                 txext=>#{ "code"=> Code,"vm" => "erltest"}}
              ),Priv)),

  #{<<"txid">>:=TxID1} = api_post_transaction(DeployTx),
  {ok, Status1, _} = api_get_tx_status(TxID1),
  ?assertMatch(#{<<"res">> := <<"ok">>}, Status1),

  GenTx=tx:pack(
          tx:sign(
          tx:construct_tx(
            #{ver=>2,
              kind=>generic,
              to=>Addr,
              from=>Addr,
              seq=>os:system_time(millisecond),
              t=>os:system_time(millisecond),
              payload=>[#{purpose=>gas, amount=>50000, cur=><<"FTT">>}],
              call=>#{function=>"notify",args=>[1024]}
             }
           ),Priv)),

  #{<<"txid">>:=TxID2} = api_post_transaction(GenTx),
  {ok, Status2, _} = api_get_tx_status(TxID2),
  ?assertMatch(#{<<"res">> := <<"ok">>}, Status2),

  DJTx=tx:pack(
         tx:sign(
         tx:construct_tx(
           #{ver=>2,
             kind=>generic,
             to=>Addr,
             from=>Addr,
             seq=>os:system_time(millisecond),
             t=>os:system_time(millisecond),
             payload=>[#{purpose=>gas, amount=>50000, cur=><<"FTT">>}],
             call=>#{function=>"delayjob",args=>[1024]}
            }),Priv)),

  #{<<"txid">>:=TxID3} = api_post_transaction(DJTx),
  {ok, #{<<"block">>:=Blkid3}=Status3, _} = api_get_tx_status(TxID3),
  ?assertMatch(#{<<"res">> := <<"ok">>}, Status3),

  Emit=tx:pack(
         tx:sign(
         tx:construct_tx(
           #{ver=>2,
             kind=>generic,
             to=>Addr,
             from=>Addr,
             seq=>os:system_time(millisecond),
             t=>os:system_time(millisecond),
             payload=>[#{purpose=>gas, amount=>50000, cur=><<"FTT">>}],
             call=>#{function=>"emit",args=>[1024]}
            }),Priv)),

  #{<<"txid">>:=TxID4} = api_post_transaction(Emit),
  {ok, Status4, _} = api_get_tx_status(TxID4),
  ?assertMatch(#{<<"res">> := <<"ok">>}, Status4),

  BadResp=tx:pack(
         tx:sign(
         tx:construct_tx(
           #{ver=>2,
             kind=>generic,
             to=>Addr,
             from=>Addr,
             seq=>os:system_time(millisecond),
             t=>os:system_time(millisecond),
             payload=>[#{purpose=>gas, amount=>50000, cur=><<"FTT">>}],
             call=>#{function=>"badnotify",args=>[1024]}
            }),Priv)),

  #{<<"txid">>:=TxID5} = api_post_transaction(BadResp),
  {ok, Status5, _} = api_get_tx_status(TxID5),
  ?assertMatch(#{<<"res">> := <<"ok">>}, Status5),

  Block3=tpapi:get_fullblock(Blkid3,get_base_url()),

  io:format("Block3 ~p~n",[Block3]),
  ?assertMatch(#{etxs:=[{<<"8001400004",_/binary>>,#{not_before:=_}}]},Block3),
  ok.

check_blocks_test(_Config) ->
  lists:map(
    fun(Node) ->
        RF=rpc:call(get_node(list_to_binary(Node)), erlang, whereis, [blockchain_reader]),
        R=test_blocks_verify(RF, last,0),
        io:format("Node ~p block verify ok, verified blocks ~p~n",[RF,R])
    end, ?TESTNET_NODES),
  ok.

test_blocks_verify(_, <<0,0,0,0,0,0,0,0>>, C) ->
  C;

test_blocks_verify(Reader, Pos, C) ->
 Blk=gen_server:call(Reader,{get_block,Pos}),
 if(is_map(Blk)) ->
     ok;
   true ->
     throw({noblock,Pos})
 end,
 {true,_}=block:verify(Blk),
 case block:verify(block:unpack(block:pack(Blk))) of
   false ->
     io:format("bad block ~p (depth ~w)~n",[Pos,C]),
     throw('BB');
   {true,_} -> 
     case Blk of
       #{header:=#{parent:=PBlk}} ->
         test_blocks_verify(Reader, PBlk, C+1);
       _ ->
         C+1
     end
 end.

crashme_test(_Config) ->
  ?assertMatch(crashme,ok).

transaction_test(_Config) ->
    % register new wallets
    Wallet = new_wallet(),
    Wallet2 = new_wallet(),
    logger("wallet: ~p, wallet2: ~p ~n", [Wallet, Wallet2]),
    %%%%%%%%%%%%%%%% make Wallet endless %%%%%%%%%%%%%%
    Cur = <<"FTT">>,
    EndlessAddress = naddress:decode(Wallet),
    TxpoolPidC4N1 =
      rpc:call(get_node(get_default_nodename()), erlang, whereis, [txpool]),
    C4N1NodePrivKey =
      rpc:call(get_node(get_default_nodename()), nodekey, get_priv, []),
  
    PatchTx = tx:sign(
      tx:construct_tx(
        #{kind=>patch,
          ver=>2,
          patches=>
          [#{<<"t">>=><<"set">>,
            <<"p">>=>[<<"current">>, <<"endless">>, EndlessAddress, Cur],
            <<"v">>=>true},
            #{<<"t">>=><<"set">>,
              <<"p">>=>[<<"current">>, <<"endless">>, EndlessAddress, <<"SK">>],
              <<"v">>=>true}]
        }
      ), C4N1NodePrivKey),
  
    {ok, PatchTxId} = gen_server:call(TxpoolPidC4N1, {new_tx, PatchTx}),
    logger("PatchTxId: ~p~n", [PatchTxId]),
    {ok, _} = wait_for_tx(PatchTxId, get_node(get_default_nodename())),
    ChainSettngs = rpc:call(get_node(get_default_nodename()), chainsettings, all, []),
    logger("ChainSettngs: ~p~n", [ChainSettngs]),
    Amount = max(1000, rand:uniform(100000)),

    LTxId = make_lstore_transaction(Wallet),
    logger("lstore txid: ~p ~n", [LTxId]),
    {ok, LStatus, _} = api_get_tx_status(LTxId),
    ?assertMatch(#{<<"res">> := <<"ok">>}, LStatus),
    logger("lstore transaction status: ~p ~n", [LStatus]),

    % send money from endless to Wallet2
    Message = <<"preved from common test">>,
    TxId3 = make_transaction(Wallet, Wallet2, Cur, Amount, Message),
    {ok, Status3, _} = api_get_tx_status(TxId3),
    ?assertMatch(#{<<"res">> := <<"ok">>}, Status3),
    logger("transaction status3: ~p ~n", [Status3]),
    Wallet2Data = api_get_wallet(Wallet2),
    logger("destination wallet [step 3]: ~p ~n", [Wallet2Data]),
    ?assertMatch(#{<<"info">> := #{<<"amount">> := #{Cur := Amount}}}, Wallet2Data),

    % make transactions from Wallet2 where we haven't SK
    Message4 = <<"without sk">>,
    TxId4 = make_transaction(Wallet2, Wallet, Cur, 1, Message4),
    logger("TxId4: ~p", [TxId4]),
    {ok, Status4, _} = api_get_tx_status(TxId4),
    logger("Status4: ~p", [Status4]),
    ?assertMatch(#{<<"res">> := <<"no_sk">>}, Status4),
    Wallet2Data4 = api_get_wallet(Wallet2),
    logger("wallet [step 4, without SK]: ~p ~n", [Wallet2Data4]),
    ?assertMatch(#{<<"info">> := #{<<"amount">> := #{Cur := Amount}}}, Wallet2Data4),

    % send SK from endless to Wallet2
    Message5 = <<"sk">>,
    TxId5 = make_transaction(Wallet, Wallet2, <<"SK">>, 1, Message5),
    logger("TxId5: ~p", [TxId5]),
    {ok, Status5, _} = api_get_tx_status(TxId5),
    logger("Status5: ~p", [Status5]),
    ?assertMatch(#{<<"res">> := <<"ok">>}, Status5),
    Wallet2Data5 = api_get_wallet(Wallet2),
    logger("wallet [step 5, received 2 SK]: ~p ~n", [Wallet2Data5]),
    ?assertMatch(#{<<"info">> := #{<<"amount">> := #{<<"SK">> := 1}}}, Wallet2Data5),

    % transaction from Wallet2 should be successful, because Wallet2 got 1 SK
    Message6 = <<"send money back">>,
    TxId6 = make_transaction(Wallet2, Wallet, Cur, 1, Message6),
    logger("TxId6: ~p", [TxId6]),
    {ok, Status6, _} = api_get_tx_status(TxId6),
    logger("Status6: ~p", [Status6]),
    Wallet2Data6 = api_get_wallet(Wallet2),
    logger("wallet [step 6, sk present]: ~p ~n", [Wallet2Data6]),
    ?assertMatch(#{<<"res">> := <<"ok">>}, Status6),
    NewAmount6 = Amount - 1,
    ?assertMatch(#{<<"info">> := #{<<"amount">> := #{Cur := NewAmount6}}}, Wallet2Data6),

    % second transaction from Wallet2 should be failed, because Wallet2 spent all SK for today
    Message7 = <<"sk test">>,
    TxId7 = make_transaction(Wallet2, Wallet, Cur, 1, Message7),
    logger("TxId7: ~p", [TxId7]),
    {ok, Status7, _} = api_get_tx_status(TxId7),
    logger("Status7: ~p", [Status7]),
    Wallet2Data7 = api_get_wallet(Wallet2),
    logger("wallet [step 7, all sk are used today]: ~p ~n", [Wallet2Data7]),
    ?assertMatch(#{<<"res">> := <<"sk_limit">>}, Status7),
    ?assertMatch(#{<<"info">> := #{<<"amount">> := #{Cur := NewAmount6}}}, Wallet2Data7),

    LSData = api_get_wallet(Wallet),
    logger("wallet [lstore]: ~p ~n", [LSData]),

    application:set_env(tptest,endless_addr,EndlessAddress),
    application:set_env(tptest,endless_addr_pk,get_wallet_priv_key()),

    dump_testnet_state().

make_lstore_transaction(From) ->
  Node = get_node(get_default_nodename()),
  Seq = get_sequence(Node, From),
  logger("seq for wallet ~p is ~p ~n", [From, Seq]),
  Tx = tx:construct_tx(
         #{
         kind => lstore,
         payload => [ ],
         patches => [
                     #{<<"t">>=><<"set">>, <<"p">>=>[<<"a">>,<<"b">>], <<"v">>=>$b},
                     #{<<"t">>=><<"set">>, <<"p">>=>[<<"a">>,<<"c">>], <<"v">>=>$c}
                    ],
         ver => 2,
         t => os:system_time(millisecond),
         seq=> Seq + 1,
         from => naddress:decode(From)
        }
  ),
  SignedTx = tx:sign(Tx, get_wallet_priv_key()),
  Res = api_post_transaction(tx:pack(SignedTx)),
  maps:get(<<"txid">>, Res, unknown).

tpiccall(TPIC, Handler, Object, Atoms) ->
    Res=tpic:call(TPIC, Handler, msgpack:pack(Object)),
    lists:filtermap(
      fun({Peer, Bin}) ->
              case msgpack:unpack(Bin, [{known_atoms, Atoms}]) of
                  {ok, Decode} ->
                      {true, {Peer, Decode}};
                  _ -> false
              end
      end, Res).

%instant_sync_test(_Config) ->
%  %instant synchronization
%  rdb_dispatcher:start_link(),
%  TPIC=rpc:call(get_node(get_default_nodename()),erlang,whereis,[tpic]),
%  Cs=tpiccall(TPIC, <<"blockchain">>,
%              #{null=><<"sync_request">>},
%              [last_hash, last_height, chain]
%             ),
%  [{Handler, Candidate}|_]=lists:filter( %first suitable will be the quickest
%                             fun({_Handler, #{chain:=_Ch,
%                                              last_hash:=_,
%                                              last_height:=_,
%                                              null:=<<"sync_available">>}}) -> true;
%                                (_) -> false
%                             end, Cs),
%  #{null:=Avail,
%    chain:=Chain,
%    last_hash:=Hash,
%    last_height:=Height}=Candidate,
%  logger("~s chain ~w h= ~w hash= ~s ~n",
%            [ Avail, Chain, Height, bin2hex:dbin2hex(Hash) ]),
%
%  Name=test_sync_ledger,
%  {ok, Pid}=ledger:start_link(
%              [{filename, "db/ledger_test_syncx2"},
%               {name, Name}
%              ]
%             ),
%  gen_server:call(Pid, '_flush'),
%  
%  Hash2=rpc:call(get_node(get_default_nodename()),ledger,check,[[]]),
%  Hash2=rpc:call(get_node(get_default_nodename()),ledger,check,[[]]),
%
%  ledger_sync:run_target(TPIC, Handler, Pid, undefined),
%
%  {ok, #{blk:=BinBlk}}=inst_sync_wait_more(#{}),
%  Hash0=case block:unpack(BinBlk) of
%          #{header:=#{ledger_hash:=V1LH}} -> V1LH;
%          #{header:=#{roots:=Roots}} -> proplists:get_value(ledger_hash,Roots)
%        end,
%  Hash1=ledger:check(Pid,[]),
%  logger("Hash ~p ~p~n",[Hash1,Hash2]),
%  ?assertMatch({ok,_},Hash1),
%  ?assertMatch({ok,_},Hash2),
%  ?assertEqual(Hash1,{ok,Hash0}),
%  ?assertEqual(Hash1,Hash2),
%  gen_server:cast(Pid, terminate),
%  done.
%  
%
%inst_sync_wait_more(A) ->
%  receive
%    {inst_sync, block, Blk} ->
%      logger("Block~n"),
%      inst_sync_wait_more(A#{blk=>Blk});
%    {inst_sync, settings} ->
%      logger("settings~n"),
%      inst_sync_wait_more(A);
%    {inst_sync, ledger} ->
%      logger("Ledger~n"),
%      inst_sync_wait_more(A);
%    {inst_sync, settings, _} ->
%      logger("Settings~n"),
%      inst_sync_wait_more(A);
%    {inst_sync, done, Res} ->
%      logger("Done ~p~n", [Res]),
%      {ok,A};
%    Any ->
%      logger("error: ~p~n", [Any]),
%      {error, Any}
%  after 10000 ->
%          timeout
%  end.


% -----------------------------------------------------------------------------

logger(Format) when is_list(Format) ->
  logger(Format, []).
  
logger(Format, Args) when is_list(Format), is_list(Args) ->
  utils:logger(Format, Args).

% -----------------------------------------------------------------------------

