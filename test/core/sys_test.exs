Code.require_file "../test_helper.exs", __DIR__

defmodule Core.SysTest do
  use ExUnit.Case

  use Core.Behaviour
  use Core.Sys.Behaviour

  def init(parent, fun) do
    Core.init_ack()
    loop(fun, parent)
  end

  def loop(fun, parent) do
    Core.Sys.receive(__MODULE__, fun, parent) do
      { __MODULE__, from, :eval } ->
        Core.reply(from, fun.())
        loop(fun, parent)
    end
  end

  def system_get_state(fun), do: fun.()

  def system_update_state(fun, update) do
    fun = update.(fun)
    { fun, fun }
  end

  def system_get_data(fun), do: fun.()

  def system_change_data(_oldfun, _mod, _oldvsn, newfun), do: newfun.()

  def system_continue(fun, parent), do: loop(fun, parent)

  def system_terminate(fun, _parent, _reason) do
    fun.()
  end

  setup_all do
    File.touch(Path.join(__DIR__, "logfile"))
    TestIO.setup_all()
  end

  setup do
    TestIO.setup()
  end

  teardown context do
    TestIO.teardown(context)
  end

  teardown_all do
    File.rm(Path.join(__DIR__, "logfile"))
    TestIO.teardown_all()
  end

  test "ping" do
    pid = Core.spawn_link(__MODULE__, fn() -> nil end)
    assert Core.Sys.ping(pid) === :pong
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "ping :gen_server" do
    { :ok, pid } = GS.start_link(fn() -> { :ok, nil } end)
  assert Core.Sys.ping(pid) === :pong
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "ping :gen_event" do
    { :ok, pid } = GE.start_link(fn() -> { :ok, nil } end)
    assert Core.Sys.ping(pid) === :pong
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "ping :gen_fsm" do
    { :ok, pid} = GFSM.start_link(fn() -> {:ok, :state, nil} end)
    assert Core.Sys.ping(pid) === :pong
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end)
    assert Core.Sys.get_state(pid) === ref
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state that raises exception" do
    exception = ArgumentError[message: "hello"]
    pid = Core.spawn_link(__MODULE__, fn() -> raise(exception, []) end)
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_state/1)} raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Core.Sys.get_state(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state that throws" do
    pid = Core.spawn_link(__MODULE__, fn() -> throw(:hello) end)
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_state/1)} raised an exception\n" <>
      "   (Core.UncaughtThrowError) uncaught throw: :hello",
      fn() -> Core.Sys.get_state(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state that exits" do
    pid = Core.spawn_link(__MODULE__, fn() -> exit(:hello) end)
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_state/1)} exited with reason: :hello",
      fn() -> Core.Sys.get_state(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state :gen_server" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Core.Sys.get_state(pid) === ref
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state :gen_event" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    assert Core.Sys.get_state(pid) === [{GE, false, ref}]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state :gen_fsm" do
    ref = make_ref()
    { :ok, pid} = GFSM.start_link(fn() -> {:ok, :state, ref} end)
    assert Core.Sys.get_state(pid) === { :state, ref }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_state" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end)
    ref2 = make_ref()
    fun = fn() -> ref2 end
    assert Core.Sys.set_state(pid, fun) === :ok
    assert Core.call(pid, __MODULE__, :eval, 500) === ref2, "state not set"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end)
    ref2 = make_ref()
    update = fn(fun) -> ( fn() -> { fun.(), ref2 } end ) end
    Core.Sys.update_state(pid, update)
    assert Core.call(pid, __MODULE__, :eval, 500) === { ref1, ref2 },
      "state not updated"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state that raises exception" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end)
    exception = ArgumentError[message: "hello"]
    update = fn(_fun) -> raise(exception, []) end
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_update_state/2)} raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Core.Sys.update_state(pid, update) end
    assert Core.call(pid, __MODULE__, :eval, 500) === ref, "state changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state that throws" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end)
    update = fn(_fun) -> throw(:hello) end
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_update_state/2)} raised an exception\n" <>
      "   (Core.UncaughtThrowError) uncaught throw: :hello",
      fn() -> Core.Sys.update_state(pid, update) end
    assert Core.call(pid, __MODULE__, :eval, 500) === ref, "state changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state that exits" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end)
    update = fn(_fun) -> exit(:hello) end
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_update_state/2)} exited with reason: :hello",
      fn() -> Core.Sys.update_state(pid, update) end
    assert Core.call(pid, __MODULE__, :eval, 500) === ref, "state changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state :gen_server" do
    ref1 = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref1 } end)
    ref2 = make_ref()
    update = fn(state) -> { state, ref2 } end
    assert Core.Sys.update_state(pid, update) === { ref1, ref2 }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state :gen_event" do
    ref1 = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref1 } end)
    ref2 = make_ref()
    update = fn({mod, id, state}) -> { mod, id, { state, ref2 } } end
    assert Core.Sys.update_state(pid, update) === [{GE, false, { ref1, ref2 } }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "update_state :gen_fsm" do
    ref1 = make_ref()
    { :ok, pid} = GFSM.start_link(fn() -> {:ok, :state, ref1} end)
    ref2 = make_ref()
    update = fn({ state_name, state_data }) ->
      { state_name, { state_data, ref2 } }
    end
    assert Core.Sys.update_state(pid, update) === { :state, { ref1, ref2 } }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end)
    status = Core.Sys.get_status(pid)
    assert status[:module] === __MODULE__
    assert status[:data] === ref
    assert status[:pid] === pid
    assert status[:name] === pid
    assert status[:sys_status] === :running
    assert status[:parent] === self()
    assert Map.has_key?(status, :dictionary)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status that raises exception" do
    exception = ArgumentError[message: "hello"]
    pid = Core.spawn_link(__MODULE__, fn() -> raise(exception, []) end)
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_data/1)} raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Core.Sys.get_status(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status that throws" do
    pid = Core.spawn_link(__MODULE__, fn() -> throw(:hello) end)
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_data/1)} raised an exception\n" <>
      "   (Core.UncaughtThrowError) uncaught throw: :hello",
      fn() -> Core.Sys.get_status(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status that exits" do
    pid = Core.spawn_link(__MODULE__, fn() -> exit(:hello) end)
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_get_data/1)} exited with reason: :hello",
      fn() -> Core.Sys.get_status(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test ":sys get_status" do
    ref = make_ref()
    { :ok, pid } = Core.start_link(__MODULE__, fn() -> ref end)
    parent = self()
    { :dictionary, pdict } = Process.info(pid, :dictionary)
    assert { :status, ^pid, { :module, Core.Sys },
      [^pdict, :running, ^parent, [], status] } = :sys.get_status(pid)
    # copy the format of gen_* :sys.status's. Length-3 list, first term is
    # header tuple, second is general information in :data tuple supplied by all
    # callbacks, and third is specific to the callback.
    assert [{ :header, header }, { :data, data1 }, { :data, data2 }] = status
    assert header === String.to_char_list!("Status for " <>
      "#{inspect(__MODULE__)} #{inspect(pid)}")
    assert List.keyfind(data1, 'Status', 0) === { 'Status', :running }
    assert List.keyfind(data1, 'Parent', 0) === { 'Parent', self() }
    assert List.keyfind(data1, 'Name', 0) === { 'Name', pid }
    assert List.keyfind(data1, 'Module', 0) === { 'Module', __MODULE__ }
    assert List.keyfind(data2, 'Module data', 0) === { 'Module data', ref }
    assert List.keyfind(data2, 'Module error', 0) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test ":sys.get_status with exception" do
    exception = ArgumentError[message: "hello"]
    pid = Core.spawn_link(__MODULE__, fn() -> raise(exception, []) end)
    assert { :status, ^pid, { :module, Core.Sys },
      [_, _, _, _, status] } = :sys.get_status(pid)
    assert [{ :header, _header }, { :data, _data1 }, { :data, data2 }] = status
    # error like 17.0 format for :sys.get_state/replace_stats
    exception2 = Core.Sys.CallbackError[action: &__MODULE__.system_get_data/1,
      reason: exception]
    assert List.keyfind(data2, 'Module error', 0) === { 'Module error',
      { :callback_failed, { Core.Sys, :format_status },
        { :error, exception2 } } }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status :gen_server" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    status = Core.Sys.get_status(pid)
    assert status[:module] === :gen_server
    assert status[:data] === ref
    assert status[:pid] === pid
    assert status[:name] === pid
    assert status[:sys_status] === :running
    assert status[:parent] === self()
    assert Map.has_key?(status, :dictionary)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status :gen_event" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    status = Core.Sys.get_status(pid)
    assert status[:module] === :gen_event
    assert status[:data] === [{ GE, false, ref}]
    assert status[:pid] === pid
    assert status[:name] === pid
    assert status[:sys_status] === :running
    assert status[:parent] === self()
    assert Map.has_key?(status, :dictionary)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status :gen_fsm" do
    ref = make_ref()
    { :ok, pid} = GFSM.start_link(fn() -> {:ok, :state, ref} end)
    status = Core.Sys.get_status(pid)
    assert status[:module] === :gen_fsm
    assert status[:data] === { :state, ref }
    assert status[:pid] === pid
    assert status[:name] === pid
    assert status[:stats] === nil
    assert status[:sys_status] === :running
    assert status[:parent] === self()
    assert Map.has_key?(status, :dictionary)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_data" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end)
    assert Core.Sys.get_data(pid) === ref
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end)
    ref2 = make_ref()
    fun = fn() -> fn() -> ref2 end end
    assert Core.Sys.suspend(pid) === :ok
    assert Core.Sys.change_data(pid, __MODULE__, nil, fun) === :ok
    assert Core.Sys.resume(pid) === :ok
    assert Core.call(pid, __MODULE__, :eval, 500) === ref2, "data not changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data that raises exception" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end)
    Core.Sys.suspend(pid)
    exception = ArgumentError[message: "hello"]
    extra = fn() -> raise(exception, []) end
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_change_data/4)} raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Core.Sys.change_data(pid, __MODULE__, nil, extra) end
    Core.Sys.resume(pid)
    assert Core.call(pid, __MODULE__, :eval, 500) === ref, "data changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data that throws" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end)
    Core.Sys.suspend(pid)
    extra = fn() -> throw(:hello) end
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_change_data/4)} raised an exception\n" <>
      "   (Core.UncaughtThrowError) uncaught throw: :hello",
      fn() -> Core.Sys.change_data(pid, __MODULE__, nil, extra) end
    Core.Sys.resume(pid)
    assert Core.call(pid, __MODULE__, :eval, 500) === ref, "data changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data that exits" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end)
    Core.Sys.suspend(pid)
    extra = fn() -> exit(:hello) end
    assert_raise Core.Sys.CallbackError,
      "#{inspect(&__MODULE__.system_change_data/4)} exited with reason: :hello",
      fn() -> Core.Sys.change_data(pid, __MODULE__, nil, extra) end
    Core.Sys.resume(pid)
    assert Core.call(pid, __MODULE__, :eval, 500) === ref, "data changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data while running" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end)
    ref2 = make_ref()
    extra = fn() -> fn() -> ref2 end end
    assert_raise ArgumentError, "#{inspect(pid)} is running",
      fn() -> Core.Sys.change_data(pid, __MODULE__, nil, extra) end
    assert Core.call(pid, __MODULE__, :eval, 500) === ref1, "data changed"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server" do
    ref1 = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref1 } end)
    Core.Sys.suspend(pid)
    ref2 = make_ref()
    extra = fn() -> { :ok, ref2 } end
    assert Core.Sys.change_data(pid, GS, nil, extra) === :ok
    Core.Sys.resume(pid)
    assert :sys.get_state(pid) === ref2
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server with raise" do
    ref1 = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref1 } end)
    Core.Sys.suspend(pid)
    exception = ArgumentError[message: "hello"]
    extra = fn() -> raise(exception, []) end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Core.Sys.change_data(pid, GS, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server with erlang badarg" do
    ref1 = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref1 } end)
    Core.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:badarg, []) end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) argument error",
      fn() -> Core.Sys.change_data(pid, GS, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server with erlang error" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:custom_erlang, []) end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ErlangError) erlang error: :custom_erlang",
      fn() -> Core.Sys.change_data(pid, GS, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server with exit" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> exit(:exit_reason) end
    assert_raise Core.Sys.CallbackError,
      "unknown function exited with reason: :exit_reason",
      fn() -> Core.Sys.change_data(pid, GS, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_server with bad return" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> :badreturn end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (MatchError) no match of right hand side value: :badreturn",
      fn() -> Core.Sys.change_data(pid, GS, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event" do
    ref1 = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref1 } end)
    :ok = Core.Sys.suspend(pid)
    ref2 = make_ref()
    extra = fn() -> { :ok, ref2 } end
    assert Core.Sys.change_data(pid, GE, nil, extra) === :ok
    Core.Sys.resume(pid)
    assert :sys.get_state(pid) === [{GE, false, ref2 }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event with raise" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    Core.Sys.suspend(pid)
    exception = ArgumentError[message: "hello"]
    extra = fn() -> raise(exception, []) end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Core.Sys.change_data(pid, GE, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event with erlang badarg" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:badarg, []) end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) argument error",
      fn() -> Core.Sys.change_data(pid, GE, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event with erlang error" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:custom_erlang, []) end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ErlangError) erlang error: :custom_erlang",
      fn() -> Core.Sys.change_data(pid, GE, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event with exit" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> exit(:exit_reason) end
    assert_raise Core.Sys.CallbackError,
      "unknown function exited with reason: :exit_reason",
      fn() -> Core.Sys.change_data(pid, GE, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_event with bad return" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> :badreturn end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (MatchError) no match of right hand side value: :badreturn",
      fn() -> Core.Sys.change_data(pid, GE, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm" do
    ref1 = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref1 } end)
    Core.Sys.suspend(pid)
    ref2 = make_ref()
    extra = fn() -> { :ok, :state, ref2 } end
    assert Core.Sys.change_data(pid, GFSM, nil, extra) === :ok
    Core.Sys.resume(pid)
    assert :sys.get_state(pid) === { :state, ref2 }
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm with raise" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    Core.Sys.suspend(pid)
    exception = ArgumentError[message: "hello"]
    extra = fn() -> raise(exception, []) end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) hello",
      fn() -> Core.Sys.change_data(pid, GFSM, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm with erlang badarg" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:badarg, []) end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ArgumentError) argument error",
      fn() -> Core.Sys.change_data(pid, GFSM, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm with erlang error" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> :erlang.error(:custom_erlang, []) end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (ErlangError) erlang error: :custom_erlang",
      fn() -> Core.Sys.change_data(pid, GFSM, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm with exit" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> exit(:exit_reason) end
    assert_raise Core.Sys.CallbackError,
      "unknown function exited with reason: :exit_reason",
      fn() -> Core.Sys.change_data(pid, GFSM, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "change_data :gen_fsm with bad return" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    Core.Sys.suspend(pid)
    extra = fn() -> :badreturn end
    assert_raise Core.Sys.CallbackError,
      "unknown function raised an exception\n" <>
      "   (MatchError) no match of right hand side value: :badreturn",
      fn() -> Core.Sys.change_data(pid, GFSM, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  ## utils

  defp close(pid) do
    Process.unlink(pid)
    ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)
    receive do
      { :DOWN, ^ref, _, _, :shutdown } ->
        :ok
    after
      500 ->
        Process.demonitor(ref, [:flush])
        Process.link(pid)
        :timeout
    end
  end

end
