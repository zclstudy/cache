-module(sharded_cache_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile([export_all]).

all() ->
    [Test || {Test, NAry} <- ?MODULE:module_info(exports), 
      Test =/= module_info,
      Test =/= init_per_suite,
      Test =/= end_per_suite,
      NAry =:= 1
   ].


init_per_suite(Config) ->
    ok = application:start(cache),
    Config.

end_per_suite(_Config) ->
    ok.


init_per_testcase(TestCase, Config) ->
    CacheName = list_to_atom("cache_" ++ atom_to_list(TestCase)),
    [{cache_name, CacheName} | Config].

end_per_testcase(_TestCase, Config) ->
    proplists:delete(cache_name, Config).

%%
%%
lifecycle_sharded_cache(_Config) ->
    ?assert(is_pid(whereis(cache_sup))),

    ?assertMatch({ok, _}, sharded_cache:start(cache1, 4)),
    ?assertMatch({error, {already_started, _}}, sharded_cache:start(cache1, 4)),

    ?assertMatch({ok, _}, sharded_cache:start(cache2, 8)),
    ?assertMatch({error, {already_started, _}}, sharded_cache:start(cache2, 8)),

    {ok, CacheShards1} = application:get_env(cache, cache_shards),
    ?assertEqual(2, maps:size(CacheShards1)),
    ?assertMatch(#{cache1 := 4, cache2 := 8}, CacheShards1),

    ?assertEqual(ok, sharded_cache:drop(cache1)),
    ?assertEqual({error, invalid_cache}, sharded_cache:drop(cache1)),

    ?assertEqual(ok, sharded_cache:drop(cache2)),
    ?assertEqual({error, invalid_cache}, sharded_cache:drop(cache2)),
    ?assertEqual({error, invalid_cache}, sharded_cache:drop(some_invalid_cache_name)),

    {ok, CacheShards2} = application:get_env(cache, cache_shards),
    ?assertEqual(0, maps:size(CacheShards2)),
    ?assertMatch(#{}, CacheShards2),
    ok.


get_shard(Config) ->
    CacheName = ?config(cache_name, Config),
    {ok, _} = sharded_cache:start(CacheName, 4),
    Shards = [cache_get_shard_1, cache_get_shard_2, cache_get_shard_3, cache_get_shard_4],
    lists:foreach(
        fun(ID) ->
            {ok, Shard} = sharded_cache:get_shard(CacheName, ID),
            ?assert(lists:member(Shard, Shards))
        end,
        lists:seq(1, 100)
    ),
    ?assertEqual({error, invalid_cache}, sharded_cache:get_shard(some_invalid_cache_name, 1)),
    ok = sharded_cache:drop(CacheName),
    ok.


get_put_delete(Config) ->
    CacheName = ?config(cache_name, Config),
    {ok, _} = sharded_cache:start(CacheName, 4),

    ?assertEqual({error, not_found}, sharded_cache:get(CacheName, key1)),
    ?assertEqual(ok, sharded_cache:put(CacheName, key1, value1)),
    ?assertEqual({ok, value1}, sharded_cache:get(CacheName, key1)),
    ?assertEqual({error, invalid_cache}, sharded_cache:get(some_invalid_cache_name, key1)),

    {ok, Shard} = sharded_cache:get_shard(CacheName, key1),
    ?assertEqual(value1, cache:get(Shard, key1)),

    ?assertEqual(ok, sharded_cache:delete(CacheName, key1)),
    ?assertEqual({error, not_found}, sharded_cache:get(CacheName, key1)),

    ok = sharded_cache:drop(CacheName),
    ok.
