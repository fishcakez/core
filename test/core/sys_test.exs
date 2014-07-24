Code.require_file "../test_helper.exs", __DIR__

defmodule Core.SysTest do
  use ExUnit.Case

  use Core.Sys

  def init(parent, debug, fun) do
    Core.init_ack()
    loop(fun, parent, debug)
  end

  def loop(fun, parent, debug) do
    Core.Sys.receive(__MODULE__, fun, parent, debug) do
      { __MODULE__, from, { :event, event } } ->
        debug = Core.Debug.event(debug, event)
        Core.reply(from, :ok)
        loop(fun, parent, debug)
      { __MODULE__, from, :eval } ->
        Core.reply(from, fun.())
        loop(fun, parent, debug)
    end
  end

  def system_get_state(fun), do: fun.()

  def system_update_state(fun, update) do
    fun = update.(fun)
    { fun, fun }
  end

  def system_get_data(fun), do: fun.()

  def system_change_data(_oldfun, _mod, _oldvsn, newfun), do: newfun.()

  def system_continue(fun, parent, debug), do: loop(fun, parent, debug)

  def system_terminate(_fun, _parent, _debug, reason) do
    exit(reason)
  end

  setup_all do
    logfile = (Path.join(__DIR__, "logfile"))
    File.touch(logfile)
    on_exit(fn() -> File.rm(Path.join(__DIR__, "logfile")) end)
    TestIO.setup_all()
  end

  setup do
    TestIO.setup()
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
    exception = ArgumentError.exception([message: "hello"])
    pid = Core.spawn_link(__MODULE__, fn() -> raise(exception) end)
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in &Core\.SysTest\.system_get_state/1\n    \*\* \(ArgumentError\) hello\n"m,
      fn() -> Core.Sys.get_state(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state that throws" do
    pid = Core.spawn_link(__MODULE__, fn() -> throw(:hello) end)
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in &Core\.SysTest\.system_get_state/1\n    \*\* \(throw\) :hello\n"m,
      fn() -> Core.Sys.get_state(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_state that exits" do
    pid = Core.spawn_link(__MODULE__, fn() -> exit(:hello) end)
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in &Core\.SysTest\.system_get_state/1\n    \*\* \(exit\) :hello\n"m,
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
    exception = ArgumentError.exception([message: "hello"])
    update = fn(_fun) -> raise(exception) end
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in &Core\.SysTest\.system_update_state/2\n    \*\* \(ArgumentError\) hello\n"m,
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
      ~r"^failure in &Core\.SysTest\.system_update_state/2\n    \*\* \(throw\) :hello\n"m,
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
      ~r"^failure in &Core\.SysTest\.system_update_state/2\n    \*\* \(exit\) :hello\n"m,
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
    assert status[:log] === []
    assert status[:stats] === nil
    assert status[:sys_status] === :running
    assert status[:parent] === self()
    assert Map.has_key?(status, :dictionary)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status with log and 2 events" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    status = Core.Sys.get_status(pid)
    assert status[:log] === [ { :event, 1}, { :event, 2} ]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status with stats and 1 cast message" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    status = Core.Sys.get_status(pid)
    stats = status[:stats]
    assert is_map(stats), "stats not returned"
    assert stats[:in] === 1
    assert stats[:out] === 0
    assert is_integer(stats[:reductions])
    assert stats[:start_time] <= stats[:current_time]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status that raises exception" do
    exception = ArgumentError.exception([message: "hello"])
    pid = Core.spawn_link(__MODULE__, fn() -> raise(exception) end)
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in &Core\.SysTest\.system_get_data/1\n    \*\* \(ArgumentError\) hello\n"m,
      fn() -> Core.Sys.get_status(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status that throws" do
    pid = Core.spawn_link(__MODULE__, fn() -> throw(:hello) end)
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in &Core\.SysTest\.system_get_data/1\n    \*\* \(throw\) :hello\n"m,
      fn() -> Core.Sys.get_status(pid) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status that exits" do
    pid = Core.spawn_link(__MODULE__, fn() -> exit(:hello) end)
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in &Core\.SysTest\.system_get_data/1\n    \*\* \(exit\) :hello\n"m,
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
    assert header === String.to_char_list("Status for " <>
      "#{inspect(__MODULE__)} #{inspect(pid)}")
    assert List.keyfind(data1, 'Status', 0) === { 'Status', :running }
    assert List.keyfind(data1, 'Parent', 0) === { 'Parent', self() }
    assert List.keyfind(data1, 'Logged events', 0) === { 'Logged events', [] }
    assert List.keyfind(data1, 'Statistics', 0) === { 'Statistics',
      :no_statistics }
    assert List.keyfind(data1, 'Name', 0) === { 'Name', pid }
    assert List.keyfind(data1, 'Module', 0) === { 'Module', __MODULE__ }
    assert List.keyfind(data2, 'Module data', 0) === { 'Module data', ref }
    assert List.keyfind(data2, 'Module error', 0) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test ":sys.get_status with exception" do
    exception = ArgumentError.exception([message: "hello"])
    pid = Core.spawn_link(__MODULE__, fn() -> raise(exception) end)
    assert { :status, ^pid, { :module, Core.Sys },
      [_, _, _, _, status] } = :sys.get_status(pid)
    assert [{ :header, _header }, { :data, _data1 }, { :data, data2 }] = status
    # error like 17.0 format for :sys.get_state/replace_stats
    action = &__MODULE__.system_get_data/1
    error =  List.keyfind(data2, 'Module error', 0)
    assert match?({'Module error',
      {:callback_failed, {Core.Sys, :format_status},
        {:error,  %Core.Sys.CallbackError{action: ^action,
            kind: :error, payload: ^exception, stacktrace: [_|_]}}}}, error)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test ":sys.get_status with throw" do
    pid = Core.spawn_link(__MODULE__, fn() -> throw(:hello) end)
    assert { :status, ^pid, { :module, Core.Sys },
      [_, _, _, _, status] } = :sys.get_status(pid)
    assert [{ :header, _header }, { :data, _data1 }, { :data, data2 }] = status
    # error like 17.0 format for :sys.get_state/replace_stats
    action = &__MODULE__.system_get_data/1
    error =  List.keyfind(data2, 'Module error', 0)
    assert match?({'Module error',
      {:callback_failed, {Core.Sys, :format_status},
        {:error,  %Core.Sys.CallbackError{action: ^action,
            kind: :throw, payload: :hello, stacktrace: [_|_]}}}}, error)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test ":sys.get_status with exit" do
    pid = Core.spawn_link(__MODULE__, fn() -> exit(:hello) end)
    assert { :status, ^pid, { :module, Core.Sys },
      [_, _, _, _, status] } = :sys.get_status(pid)
    assert [{ :header, _header }, { :data, _data1 }, { :data, data2 }] = status
    # error like 17.0 format for :sys.get_state/replace_stats
    action = &__MODULE__.system_get_data/1
    error =  List.keyfind(data2, 'Module error', 0)
    assert match?({'Module error',
      {:callback_failed, {Core.Sys, :format_status},
        {:error,  %Core.Sys.CallbackError{action: ^action,
            kind: :exit, payload: :hello, stacktrace: [_|_]}}}}, error)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test ":sys.get_status with log" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500) 
    assert { :status, ^pid, { :module, Core.Sys },
      [_, _, _, debug, status] } = :sys.get_status(pid)
    assert [{ :header, _header }, { :data, data1 }, { :data, _data2 }] = status
    # This is how gen_* displays the log
    sys_log = :sys.get_debug(:log, debug, [])
    assert List.keyfind(data1, 'Logged events', 0) === { 'Logged events',
      sys_log }
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
    assert status[:log] === []
    assert status[:stats] === nil
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
    assert status[:log] === []
    assert status[:stats] === nil
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
    assert status[:log] === []
    assert status[:stats] === nil
    assert status[:sys_status] === :running
    assert status[:parent] === self()
    assert Map.has_key?(status, :dictionary)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status :gen_server with log" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    send(pid, { :msg, 1 })
    send(pid, { :msg, 2 })
    status = Core.Sys.get_status(pid)
    assert status[:log] === [{ :in, { :msg, 1 } }, { :noreply, ref },
      { :in, { :msg, 2 } }, { :noreply, ref }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_status :gen_fsm with log" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    send(pid, { :msg, 1 })
    send(pid, { :msg, 2 })
    status = Core.Sys.get_status(pid)
    assert status[:log] === [{ :in, { :msg, 1 } }, :return,
      { :in, { :msg, 2 } }, :return]
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
    exception = ArgumentError.exception([message: "hello"])
    extra = fn() -> raise(exception) end
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in &Core\.SysTest\.system_change_data/4\n    \*\* \(ArgumentError\) hello\n"m,
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
      ~r"^failure in &Core\.SysTest\.system_change_data/4\n    \*\* \(throw\) :hello\n"m,
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
      ~r"^failure in &Core\.SysTest\.system_change_data/4\n    \*\* \(exit\) :hello\n"m,
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
    exception = ArgumentError.exception([message: "hello"])
    extra = fn() -> raise(exception) end
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in unknown function\n    \*\* \(exit\) an exception was raised:\n        \*\* \(ArgumentError\) hello\n"m,
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
      ~r"^failure in unknown function\n    \*\* \(exit\) an exception was raised:\n        \*\* \(ArgumentError\) argument error\n"m,
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
      ~r"^failure in unknown function\n    \*\* \(exit\) an exception was raised:\n        \*\* \(ErlangError\) erlang error: :custom_erlang\n"m,
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
      "failure in unknown function\n    ** (exit) :exit_reason",
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
      "failure in unknown function\n    ** (ErlangError) erlang error: :badreturn",
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
    exception = ArgumentError.exception([message: "hello"])
    extra = fn() -> raise(exception) end
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in unknown function\n    \*\* \(exit\) an exception was raised:\n        \*\* \(ArgumentError\) hello\n"m,
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
      ~r"^failure in unknown function\n    \*\* \(exit\) an exception was raised:\n        \*\* \(ArgumentError\) argument error\n"m,
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
      ~r"^failure in unknown function\n    \*\* \(exit\) an exception was raised:\n        \*\* \(ErlangError\) erlang error: :custom_erlang\n"m,
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
      ~r"^failure in unknown function\n    \*\* \(exit\) :exit_reason$"m,
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
      ~r"^failure in unknown function\n    \*\* \(exit\) an exception was raised:\n        \*\* \(MatchError\) no match of right hand side value: :badreturn\n"m,
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
    exception = ArgumentError.exception([message: "hello"])
    extra = fn() -> raise(exception) end
    assert_raise Core.Sys.CallbackError,
      ~r"^failure in unknown function\n    \*\* \(exit\) an exception was raised:\n        \*\* \(ArgumentError\) hello\n"m,
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
      ~r"^failure in unknown function\n    \*\* \(exit\) an exception was raised:\n        \*\* \(ArgumentError\) argument error"m,
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
      ~r"^failure in unknown function\n    \*\* \(exit\) an exception was raised:\n        \*\* \(ErlangError\) erlang error: :custom_erlang"m,
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
      "failure in unknown function\n    ** (exit) :exit_reason",
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
      "failure in unknown function\n    ** (ErlangError) erlang error: :badreturn",
      fn() -> Core.Sys.change_data(pid, GFSM, nil, extra) end
    Core.Sys.resume(pid)
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "parent exit" do
    ref = make_ref()
    fun = fn() -> Process.flag(:trap_exit, true) ; ref end
    pid = Core.spawn_link(__MODULE__, fun)
    assert Core.call(pid, __MODULE__, :eval, 500) === ref, "trap_exit not set"
    trap = Process.flag(:trap_exit, true)
    Process.exit(pid, :exit_reason)
    assert_receive { :EXIT, ^pid, reason }, 100, "process did not exit"
    assert reason === :exit_reason
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "get_log with 0 events" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
    [{ :debug, [{ :log, 10 }] }])
    assert Core.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log with 2 events" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Core.Sys.get_log(pid) === [{ :event, 1 }, { :event, 2 }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log with no logging and 2 events" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Core.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_server with 0 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    assert Core.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_server with 2 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    send(pid, 1)
    send(pid, 2)
    assert Core.Sys.get_log(pid) === [{ :in, 1 }, { :noreply, ref },
      { :in, 2 }, { :noreply, ref }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_server with no logging" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Core.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_event with no logging (can never log)" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    assert Core.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_fsm with 0 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    assert Core.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_fsm with 2 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    send(pid, 1)
    send(pid, 2)
    assert Core.Sys.get_log(pid) === [{ :in, 1 }, :return, { :in, 2 }, :return]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_log :gen_fsm with no logging" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    assert Core.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "print_log with 2 events" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log:\n" <>
    "** Core.Debug #{inspect(pid)} #{inspect({ :event, 1 })}\n" <>
    "** Core.Debug #{inspect(pid)} #{inspect({ :event, 2 })}\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log with 0 events" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log with no logging and 2 events" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log with cast message in" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log:\n" <>
    "** Core.Debug #{inspect(pid)} message in: :hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log with call message in" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :in, :hello, self() } }, 500)
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log:\n" <>
    "** Core.Debug #{inspect(pid)} message in (from #{inspect(self())}): " <>
    ":hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log with message out" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :out, :hello, self() } }, 500)
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log:\n" <>
    "** Core.Debug #{inspect(pid)} message out (to #{inspect(self())}): " <>
    ":hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log :gen_server with 0 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log :gen_server with 2 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    send(pid, 1)
    send(pid, 2)
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    erl_pid = inspect_erl(pid)
    erl_ref = inspect_erl(ref)
    report = "** Core.Debug #{inspect(pid)} event log:\n" <>
    "*DBG* #{erl_pid} got 1\n" <>
    "*DBG* #{erl_pid} new state #{erl_ref}\n" <>
    "*DBG* #{erl_pid} got 2\n" <>
    "*DBG* #{erl_pid} new state #{erl_ref}\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log :gen_server with no logging" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
   assert TestIO.binread() === report
  end

  test "print_log :gen_event with no logging (can never log)" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
   assert TestIO.binread() === report
  end

  test "print_log :gen_fsm with 0 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log :gen_fsm with 2 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    send(pid, 1)
    send(pid, 2)
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    erl_pid = inspect_erl(pid)
    report = "** Core.Debug #{inspect(pid)} event log:\n" <>
    "*DBG* #{erl_pid} got 1 in state state\n" <>
    "*DBG* #{erl_pid} switched to state state\n" <>
    "*DBG* #{erl_pid} got 2 in state state\n" <>
    "*DBG* #{erl_pid} switched to state state\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "print_log :gen_fsm with no logging" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    assert Core.Sys.print_log(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} event log is empty\n" <>
    "\n"
   assert TestIO.binread() === report
  end

  test "set_log 10 with 2 events" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end)
    assert Core.Sys.set_log(pid, 10) === :ok
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Core.Sys.get_log(pid) === [{ :event, 1 }, { :event, 2 }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 1 with 2 events" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end)
    assert Core.Sys.set_log(pid, 1) === :ok
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Core.Sys.get_log(pid) === [{ :event, 2 }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 0 with 1 event before and 1 event after" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log, 10 }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert Core.Sys.set_log(pid, 0) === :ok
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Core.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 10 :gen_server with 2 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Core.Sys.set_log(pid, 10) === :ok
    send(pid, 1)
    send(pid, 2)
    assert Core.Sys.get_log(pid) === [{ :in, 1 }, { :noreply, ref },
      { :in, 2 }, { :noreply, ref }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 1 :gen_server with 2 events" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Core.Sys.set_log(pid, 1) === :ok
    send(pid, 1)
    assert Core.Sys.get_log(pid) === [{ :noreply, ref }]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 0 :gen_server with 2 events before and 2 event after" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [{ :log, 10 }])
    send(pid, 1)
    assert Core.Sys.set_log(pid, 0) === :ok
    send(pid, 2)
    assert Core.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 10 :gen_fsm with 4 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    assert Core.Sys.set_log(pid, 10) === :ok
    send(pid, 1)
    send(pid, 2)
    assert Core.Sys.get_log(pid) === [{ :in, 1 }, :return, { :in, 2 }, :return]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 1 :gen_fsm with 2 events" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    assert Core.Sys.set_log(pid, 1) === :ok
    send(pid, 1)
    assert Core.Sys.get_log(pid) === [:return]
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_log 0 :gen_fsm with 2 events before and 2 event after" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end,
      [{ :log, 10 }])
    send(pid, 1)
    assert Core.Sys.set_log(pid, 0) === :ok
    send(pid, 2)
    assert Core.Sys.get_log(pid) === []
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats with 0 events" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    stats = Core.Sys.get_stats(pid)
    assert stats[:in] === 0
    assert stats[:out] === 0
    assert is_integer(stats[:reductions])
    assert stats[:start_time] <= stats[:current_time]
    assert Map.size(stats) === 5
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats with no stats" do
    ref = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref end)
    assert Core.Sys.get_stats(pid) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats with cast message in" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    stats = Core.Sys.get_stats(pid)
    assert stats[:in] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats with call message in" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :in, :hello, self() } }, 500)
    stats = Core.Sys.get_stats(pid)
    assert stats[:in] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats with message out" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :out, :hello, self() } }, 500)
    stats = Core.Sys.get_stats(pid)
    assert stats[:out] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats :gen_server with no stats" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end)
    assert Core.Sys.get_stats(pid) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats :gen_server with 1 message in" do
    ref = make_ref()
    { :ok, pid } = GS.start_link(fn() -> { :ok, ref } end, [:statistics])
    send(pid, 1)
    stats = Core.Sys.get_stats(pid)
    assert stats[:in] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats :gen_event with no stats" do
    ref = make_ref()
    { :ok, pid } = GE.start_link(fn() -> { :ok, ref } end)
    assert Core.Sys.get_stats(pid) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats :gen_fsm with no stats" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref } end)
    assert Core.Sys.get_stats(pid) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "get_stats :gen_fsm with 1 message in" do
    ref = make_ref()
    { :ok, pid } = GFSM.start_link(fn() -> { :ok, :state, ref}  end,
      [:statistics])
    send(pid, 1)
    stats = Core.Sys.get_stats(pid)
    assert stats[:in] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "print_stats with one of each event" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :in, :hello, self() } }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :out, :hello, self() } }, 500)
    assert Core.Sys.print_stats(pid) === :ok
    assert close(pid) === :ok
    output = TestIO.binread()
    pattern = "\\A\\*\\* Core.Debug #{inspect(pid)} statistics:\n" <>
    "   Start Time: \\d\\d\\d\\d-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d\n" <>
    "   Current Time: \\d\\d\\d\\d-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d\n" <>
    "   Messages In: 2\n" <>
    "   Messages Out: 1\n" <>
    "   Reductions: \\d+\n" <>
    "\n\\z"
    regex = Regex.compile!(pattern)
    assert Regex.match?(regex, output),
      "#{inspect(regex)} not found in #{output}"
  end

  test "print_stats with no stats" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end)
    assert Core.Sys.print_stats(pid) === :ok
    assert close(pid) === :ok
    report = "** Core.Debug #{inspect(pid)} statistics not active\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "set_stats true with a cast message in" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end)
    assert Core.Sys.set_stats(pid, true) === :ok
    :ok = Core.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    stats = Core.Sys.get_stats(pid)
    assert stats[:in] === 1
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "set_stats false after a cast message in" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :stats, true }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :in, :hello } }, 500)
    assert Core.Sys.set_stats(pid, false) === :ok
    assert Core.Sys.get_stats(pid) === nil
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "log_file" do
    ref1 = make_ref()
    file = Path.join(__DIR__, "logfile")
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :log_file, file }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert Core.Sys.set_log_file(pid, nil) === :ok
    log = "** Core.Debug #{inspect(pid)} #{inspect({ :event, 1 })}\n"
    assert File.read!(file) === log
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert Core.Sys.set_log_file(pid, file) === :ok
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 3 } }, 500)
    assert close(pid) === :ok
    log = "** Core.Debug #{inspect(pid)} #{inspect({ :event, 3 })}\n"
    assert File.read!(file) === log
    assert TestIO.binread() === <<>>
  end

  test "log_file bad file" do
    ref1 = make_ref()
    file = Path.join(Path.join(__DIR__, "baddir"), "logfile")
    pid = Core.spawn_link( __MODULE__, fn() -> ref1 end)
    assert_raise ArgumentError, "could not open file: #{inspect(file)}",
      fn() -> Core.Sys.set_log_file(pid, file) end
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "trace" do
    ref1 = make_ref()
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
    [{ :debug, [{ :trace, true }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert Core.Sys.set_trace(pid, false) === :ok
    report1 = "** Core.Debug #{inspect(pid)} #{inspect({ :event, 1 })}\n"
    assert TestIO.binread() === report1
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    assert TestIO.binread() === report1
    assert Core.Sys.set_trace(pid, true) === :ok
    :ok = Core.call(pid, __MODULE__, { :event, { :in, :hello, self() } }, 500)
    assert close(pid) === :ok
    report2 =  "** Core.Debug #{inspect(pid)} " <>
    "message in (from #{inspect(self())}): :hello\n"
    assert TestIO.binread() === "#{report1}#{report2}"
  end

  test "hook" do
    ref1 = make_ref()
    hook = fn(to, event, process) -> send(to, { process, event }) end
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :hook, { hook, self() } }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert_received { ^pid, { :event, 1 } }, "hook did not send message"
    assert Core.Sys.set_hook(pid, hook, nil) === :ok
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    refute_received { ^pid, { :event, 2 } },
      "set_hook nil did not stop hook"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "hook set_hook changes hook state" do
    ref1 = make_ref()
    hook = fn(to, event, process) -> send(to, { process, event }) end
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :hook, { hook, self() } }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert_received { ^pid, { :event, 1 } }, "hook did not send message"
    assert Core.Sys.set_hook(pid, hook, pid)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    refute_received { ^pid, { :event, 2 } },
      "strt_hook did not change hook state"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "hook raises" do
    ref1 = make_ref()
    hook = fn(_to, :raise, _process) ->
      raise(ArgumentError, [])
      (to, event, process) ->
        send(to, { process, event })
    end
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :hook, { hook, self() } }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert_received { ^pid, { :event, 1 } }, "hook did not send message"
    :ok = Core.call(pid, __MODULE__, { :event, :raise }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    refute_received { ^pid, { :event, 2 } }, "hook raise did not stop it"
    assert close(pid) === :ok
    assert TestIO.binread() === <<>>
  end

  test "hook done" do
    ref1 = make_ref()
    hook = fn(_to, :done, _process) ->
      :done
      (to, event, process) ->
        send(to, { process, event })
    end
    pid = Core.spawn_link(__MODULE__, fn() -> ref1 end,
      [{ :debug, [{ :hook, { hook, self() } }] }])
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 1 } }, 500)
    assert_received { ^pid, { :event, 1 } }, "hook did not send message"
    :ok = Core.call(pid, __MODULE__, { :event, :done }, 500)
    :ok = Core.call(pid, __MODULE__, { :event, { :event, 2 } }, 500)
    refute_received { ^pid, { :event, 2 } }, "hook done did not stop it"
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

  defp inspect_erl(term) do
    :io_lib.format('~p', [term])
      |> List.flatten()
      |> List.to_string()
  end

end
