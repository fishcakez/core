Code.require_file "test_helper.exs", __DIR__

defmodule CoreTest do
  use ExUnit.Case

  use Core.Behaviour
  require Core.Debug

  def init(parent, debug, fun) do
      fun.(parent, debug)
  end

  def continue(fun, parent, debug) do
    fun.(parent, debug)
  end

  setup_all do
    TestIO.setup_all()
  end

  setup do
    TestIO.setup()
  end

  teardown context do
    TestIO.teardown(context)
  end

  teardown_all do
    TestIO.teardown_all()
  end

  test "start_link with init_ack/0" do
    starter = self()
    fun = fn(parent, _debug) ->
      Core.init_ack()
      send(starter, { :parent, parent })
      close()
    end
    assert { :ok, pid } = Core.start_link(__MODULE__, fun)
    assert_receive { :parent, ^starter }, 200, "parent not starter"
    assert linked?(pid), "child not linked"
    assert :normal === close(pid), "close failed"
    assert TestIO.binread() === <<>>
  end

  test "start_link with timeout" do
    fun = fn(_parent, _debug) ->
      :timer.sleep(5000)
    end
    assert { :error, :timeout } = Core.start_link(__MODULE__, fun,
      [{ :timeout, 1 }]), "didn't timeout"
    assert TestIO.binread() === <<>>
  end

  test "start_link with init_ignore" do
    fun = fn(_parent, _debug) ->
      Core.init_ignore()
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, true)
    assert :ignore === Core.start_link(__MODULE__, fun)
    assert_receive { :EXIT, _child, :normal }, 200, "init_ignore did not exit"
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
 end

  test "start_link with init_ack/1" do
    fun = fn(_parent, _debug) ->
      Core.init_ack(:extra_data)
      close()
    end
    assert { :ok, pid, :extra_data } = Core.start_link(__MODULE__, fun)
    assert close(pid) === :normal, "close failed"
    assert TestIO.binread() === <<>>
  end

  test "start_link with init_stop" do
    fun = fn(parent, debug) ->
      Core.init_stop(__MODULE__, parent, debug, nil, :init_error)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    assert { :error, :init_error } = Core.start_link(__MODULE__, fun)
    assert_receive { :EXIT, _pid, :init_error }, 200, "init_stop did not exit"
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "start_link register local name" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      close()
    end
    opts = [local: :core_start_link]
    assert { :ok, pid1 } = Core.start_link(__MODULE__, fun, opts)
    assert Core.whereis(:core_start_link) === pid1
    trap = Process.flag(:trap_exit, true)
    assert { :error, { :already_started, ^pid1 } } = Core.start_link(__MODULE__,
      fun, opts)
    assert_receive { :EXIT, _pid2, :normal }, 200,
      "already started did not exit normally"
    Process.flag(:trap_exit, trap)
    assert close(pid1) === :normal
    assert TestIO.binread() === <<>>
  end

  test "start_link register global name" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      close()
    end
    opts = [global: :core_start_link]
    assert { :ok, pid1 } = Core.start_link(__MODULE__, fun, opts)
    assert Core.whereis({ :global, :core_start_link }) === pid1
    trap = Process.flag(:trap_exit, true)
    assert { :error, { :already_started, ^pid1 } } = Core.start_link(__MODULE__,
      fun, opts)
    assert_receive { :EXIT, _pid2, :normal }, 200,
      "already started did not exit normally"
    Process.flag(:trap_exit, trap)
    assert close(pid1) === :normal
    assert TestIO.binread() === <<>>
  end

  test "start_link register via name" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      close()
    end
    opts = [{ :via, { :global, :core_start_link_via } }]
    assert { :ok, pid1 } = Core.start_link(__MODULE__, fun, opts)
    assert Core.whereis({ :via, :global, :core_start_link_via }) === pid1
    trap = Process.flag(:trap_exit, true)
    assert { :error, { :already_started, ^pid1 } } = Core.start_link(__MODULE__,
      fun, opts)
    assert_receive { :EXIT, _pid2, :normal }, 200,
      "already started did not exit normally"
    Process.flag(:trap_exit, trap)
    assert close(pid1) === :normal
    assert TestIO.binread() === <<>>
  end

  test "start with init_ack/0" do
    starter = self()
    fun = fn(parent, _debug) ->
      Core.init_ack()
      send(starter, { :parent, parent })
      close()
    end
    { :ok, pid } = Core.start(__MODULE__, fun)
    assert_receive { :parent, ^pid }, 200, "parent not self()"
    refute linked?(pid), "child linked"
    assert close(pid) === :normal, "close failed"
    assert TestIO.binread() === <<>>
  end

  test "start with timeout" do
    fun = fn(_parent, _debug) ->
      :timer.sleep(5000)
    end
    assert { :error, :timeout } = Core.start(__MODULE__, fun,
      [{ :timeout, 1 }]), "didn't timeout"
    assert TestIO.binread() === <<>>
  end


  test "start register local name" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      close()
    end
    opts = [local: :core_start]
    assert { :ok, pid1 } = Core.start(__MODULE__, fun, opts)
    assert Core.whereis(:core_start) === pid1
    assert { :error, { :already_started, ^pid1 } } = Core.start_link(__MODULE__,
      fun, opts)
    assert close(pid1) === :normal
    assert TestIO.binread() === <<>>
  end

  test "start with link" do
    starter = self()
    fun = fn(parent, _debug) ->
      send(starter, { :parent, parent })
      Core.init_ack()
      close()
    end
    { :ok, pid } = Core.start(__MODULE__, fun, [{ :spawn_opt, [:link] }])
    assert_received { :parent, ^pid }, "parent not self()"
    assert linked?(pid), "child not linked"
    assert :normal === close(pid), "close failed"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link with init_ack/0" do
    starter = self()
    fun = fn(parent, _debug) ->
      Core.init_ack()
      send(starter, { :parent, parent })
      close()
    end
    pid = Core.spawn_link(__MODULE__, fun)
    assert_receive { :parent, ^starter }, 200, "parent not starter"
    assert linked?(pid), "child not linked"
    assert close(pid) === :normal, "close failed"
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link with init_ignore" do
    fun = fn(_parent, _debug) ->
      Core.init_ignore()
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, true)
    pid = Core.spawn_link(__MODULE__, fun)
    assert_receive { :EXIT, ^pid, :normal }, 200, "init_ignore did not exit"
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
 end

  test "spawn_link with init_ack/1" do
    fun = fn(_parent, _debug) ->
      Core.init_ack(:extra_data)
      close()
    end
    pid = Core.spawn_link(__MODULE__, fun)
    assert close(pid) === :normal, "close failed"
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link with init_stop" do
    fun = fn(parent, debug) ->
      Core.init_stop(__MODULE__, parent, debug, nil, :init_error)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun)
    assert_receive { :EXIT, ^pid, :init_error }, 200, "init_stop did not exit"
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    report = "** #{erl_inspect(__MODULE__)} #{erl_inspect(pid)} is terminating\n" <>
      "** Last event was #{erl_inspect(nil)}\n" <>
      "** Arguments == #{erl_inspect(nil)}\n" <>
      "** Process   == #{erl_inspect(pid)}\n" <>
      "** Parent    == #{erl_inspect(self())}\n" <>
      "** Reason for termination == \n"<>
      "#{List.to_string(:io_lib.format('** ~p', [:init_error]))}\n\n"
    assert TestIO.binread() === report
  end

  test "spawn_link with init_stop and debug" do
    fun = fn(parent, debug) ->
      event = :test_event
      debug = Core.Debug.event(debug, event)
      Core.init_stop(__MODULE__, parent, debug, nil, :init_error, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun, [{ :debug, [{ :log, 10 }] }])
    assert_receive { :EXIT, ^pid, reason }, 200, "init_stop did not exit"
    assert reason === :init_error
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    output = TestIO.binread()
    report = "** #{erl_inspect(__MODULE__)} #{erl_inspect(pid)} is terminating\n" <>
      "** Last event was #{erl_inspect(:test_event)}\n" <>
      "** Arguments == #{erl_inspect(nil)}\n" <>
      "** Process   == #{erl_inspect(pid)}\n" <>
      "** Parent    == #{erl_inspect(self())}\n" <>
      "** Reason for termination == \n"<>
      "#{List.to_string(:io_lib.format('** ~p', [reason]))}\n\n"
    assert String.contains?(output, [report])
    log = "** Core.Debug #{inspect(pid)} event log:\n" <>
      "** Core.Debug #{inspect(pid)} :test_event\n\n"
    assert String.contains?(output, [log])
    assert byte_size(output) === (byte_size(report) + byte_size(log))
      "unexpected output in:\n #{output}"
  end

  test "spawn_link with normal init_stop and debug" do
    fun = fn(parent, debug) ->
      event = :test_event
      debug = Core.Debug.event(debug, event)
      Core.init_stop(__MODULE__, parent, debug, nil, :normal, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun, [{ :debug, [{ :log, 10 }] }])
    assert_receive { :EXIT, ^pid, reason }, 200, "init_stop did not exit"
    assert reason === :normal
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link with shutdown init_stop and debug" do
    fun = fn(parent, debug) ->
      event = :test_event
      debug = Core.Debug.event(debug, event)
      Core.init_stop(__MODULE__, parent, debug, nil, :shutdown, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun, [{ :debug, [{ :log, 10 }] }])
    assert_receive { :EXIT, ^pid, reason }, 200, "init_stop did not exit"
    assert reason === :shutdown
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link with shutdown term init_stop and debug" do
    fun = fn(parent, debug) ->
      event = :test_event
      debug = Core.Debug.event(debug, event)
      Core.init_stop(__MODULE__, parent, debug, nil, { :shutdown, nil }, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun, [{ :debug, [{ :log, 10 }] }])
    assert_receive { :EXIT, ^pid, reason }, 200, "init_stop did not exit"
    assert reason === { :shutdown, nil }
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link register local name" do
    starter = self()
    fun = fn(_parent, _debug) ->
      send(starter, { :registered, self() })
      Core.init_ack()
      close()
    end
    name = :core_spawn_link
    pid1 = Core.spawn_link(__MODULE__, fun, local: name)
    assert_receive { :registered, ^pid1 }, 200, "did not register"
    assert Core.whereis(name) === pid1
    pid2 = Core.spawn_link(__MODULE__, fun, local: name)
    ref = Process.monitor(pid2)
    assert_receive { :DOWN, ^ref, _, _, :normal }, 200,
      "already registered did not exit with reason :normal"
    refute_received { :registered, ^pid2 },
      "already started did not prevent init"
    refute_received { :ack, ^pid2, _ }, "already started sent init_ack"
    assert close(pid1) === :normal
    assert TestIO.binread() === <<>>
  end

  test "spawn with init_ack/0" do
    starter = self()
    fun = fn(parent, _debug) ->
      Core.init_ack()
      send(starter, { :parent, parent })
      close()
    end
    pid = Core.spawn(__MODULE__, fun)
    assert_receive { :parent, ^pid }, 200, "parent not self()"
    refute linked?(pid), "child linked"
    assert close(pid) === :normal, "close failed"
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn register local name" do
    starter = self()
    fun = fn(_parent, _debug) ->
      send(starter, { :registered, self() })
      Core.init_ack()
      close()
    end
    name = :core_spawn
    pid1 = Core.spawn(__MODULE__, fun, local: name)
    assert_receive { :registered, ^pid1 }, 200, "did not register"
    assert Core.whereis(name) === pid1
    pid2 = Core.spawn(__MODULE__, fun, local: name)
    ref = Process.monitor(pid2)
    assert_receive { :DOWN, ^ref, _, _, :normal }, 200,
      "already registered did not exit with reason :normal"
    refute_received { :registered, ^pid2 },
      "already started did not prevent init"
    refute_received { :ack, ^pid2, _ }, "already started sent init_ack"
    assert close(pid1) === :normal
    assert TestIO.binread() === <<>>
  end

  test "spawn with link" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      close()
    end
    pid = Core.spawn(__MODULE__, fun, [{ :spawn_opt, [:link] }])
    assert linked?(pid), "child not linked"
    assert :normal === close(pid), "close failed"
    assert TestIO.binread() === <<>>
  end

  test "stop" do
    fun = fn(parent, debug) ->
      Core.init_ack()
      Core.stop(__MODULE__, nil, parent, debug, :error)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun)
    assert_receive { :EXIT, ^pid, :error }, 200, "stop did not exit"
    Process.flag(:trap_exit, trap)
    report = "** #{erl_inspect(__MODULE__)} #{erl_inspect(pid)} is terminating\n" <>
      "** Last event was #{erl_inspect(nil)}\n"<>
      "** State   == #{erl_inspect(nil)}\n" <>
      "** Process == #{erl_inspect(pid)}\n" <>
      "** Parent  == #{erl_inspect(self())}\n" <>
      "** Reason for termination == \n"<>
      "#{List.to_string(:io_lib.format('** ~p', [:error]))}\n\n"
    assert TestIO.binread() === report
  end

  test "stop and debug" do
    fun = fn(parent, debug) ->
      Core.init_ack()
      event = :test_event
      debug = Core.Debug.event(debug, event)
      Core.stop(__MODULE__, nil, parent, debug, :error, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun, [{ :debug, [{ :log, 10 }] }])
    assert_receive { :EXIT, ^pid, reason }, 200, "stop did not exit"
    assert reason === :error
    Process.flag(:trap_exit, trap)
    output = TestIO.binread()
    report = "** #{erl_inspect(__MODULE__)} #{erl_inspect(pid)} is terminating\n" <>
      "** Last event was #{erl_inspect(:test_event)}\n"<>
      "** State   == #{erl_inspect(nil)}\n" <>
      "** Process == #{erl_inspect(pid)}\n" <>
      "** Parent  == #{erl_inspect(self())}\n" <>
      "** Reason for termination == \n"<>
      "#{List.to_string(:io_lib.format('** ~p', [reason]))}\n\n"
    assert String.contains?(output, [report])
    log = "** Core.Debug #{inspect(pid)} event log:\n" <>
      "** Core.Debug #{inspect(pid)} :test_event\n\n"
    assert String.contains?(output, [log])
    assert byte_size(output) === (byte_size(report) + byte_size(log))
      "unexpected output in:\n #{output}"
  end

  test "stop with normal and debug" do
    fun = fn(parent, debug) ->
      Core.init_ack()
      event = :test_event
      debug = Core.Debug.event(debug, event)
      Core.stop(__MODULE__, nil, parent, debug, :normal, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun, [{ :debug, [{ :log, 10 }] }])
    assert_receive { :EXIT, ^pid, reason }, 200, "stop did not exit"
    assert reason === :normal
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "stop with shutdown and debug" do
    fun = fn(parent, debug) ->
      Core.init_ack()
      event = :test_event
      debug = Core.Debug.event(debug, event)
      Core.stop(__MODULE__, nil, parent, debug, :shutdown, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun, [{ :debug, [{ :log, 10 }] }])
    assert_receive { :EXIT, ^pid, reason }, 200, "stop did not exit"
    assert reason === :shutdown
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "stop with shutdown term and debug" do
    fun = fn(parent, debug) ->
      Core.init_ack()
      event = :test_event
      debug = Core.Debug.event(debug, event)
      Core.stop(__MODULE__, nil, parent, debug, { :shutdown, nil }, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun, [{ :debug, [{ :log, 10 }] }])
    assert_receive { :EXIT, ^pid, reason }, 200, "stop did not exit"
    assert reason === { :shutdown, nil }
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "uncaught exception" do
    exception = ArgumentError.exception([message: "hello"])
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      raise exception
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    assert { ^exception, stack } = reason
    assert { __MODULE__, _, _, _ } = hd(stack),
      "stacktrace not from __MODULE__"
    Process.flag(:trap_exit, trap)
    report = "** Core #{erl_inspect(pid)} is terminating\n" <>
      "** Module  == #{erl_inspect(__MODULE__)}\n" <>
      "** Process == #{erl_inspect(pid)}\n" <>
      "** Parent  == #{erl_inspect(self())}\n" <>
      "** Reason for termination == \n" <>
      "#{List.to_string(:io_lib.format('** ~p', [reason]))}\n\n"
    assert TestIO.binread() === report
  end

  test "uncaught throw" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      throw(:thrown)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    exception = Core.UncaughtThrowError.exception([actual: :thrown])
    assert { ^exception, stack } = reason
    assert { __MODULE__, _, _, _ } = hd(stack),
      "stacktrace not from __MODULE__"
    Process.flag(:trap_exit, trap)
    report = "** Core #{erl_inspect(pid)} is terminating\n" <>
      "** Module  == #{erl_inspect(__MODULE__)}\n" <>
      "** Process == #{erl_inspect(pid)}\n" <>
      "** Parent  == #{erl_inspect(self())}\n" <>
      "** Reason for termination == \n"<>
      "#{List.to_string(:io_lib.format('** ~p', [reason]))}\n\n"
    assert TestIO.binread() === report
  end

  test "uncaught exit" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      exit(:exited)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    assert :exited = reason, "reason is not exited"
    Process.flag(:trap_exit, trap)
     assert TestIO.binread() === <<>>
  end

  test "uncaught exception after hibernate" do
    exception = ArgumentError.exception([message: "hello"])
    fun = fn(parent, debug) ->
      Core.init_ack()
      # send message to self to wake up immediately
      send(self(), :awaken)
      fun2 = fn(_parent, _debug) -> raise ArgumentError, [message: "hello"] end
      Core.hibernate(__MODULE__, :continue, fun2, parent, debug)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    assert { ^exception, stack } = reason
    assert { __MODULE__, _, _, _ } = hd(stack),
      "stacktrace not from __MODULE__"
    Process.flag(:trap_exit, trap)
    report = "** Core #{erl_inspect(pid)} is terminating\n" <>
      "** Module  == #{erl_inspect(__MODULE__)}\n" <>
      "** Process == #{erl_inspect(pid)}\n" <>
      "** Parent  == #{erl_inspect(self())}\n" <>
      "** Reason for termination == \n"<>
      "#{List.to_string(:io_lib.format('** ~p', [reason]))}\n\n"
    assert TestIO.binread() === report
  end

  test "uncaught throw after hibernate" do
    fun = fn(parent, debug) ->
      Core.init_ack()
      # send message to self to wake up immediately
      send(self(), :awaken)
      fun2 = fn(_parent, _debug) -> throw(:thrown) end
      Core.hibernate(__MODULE__, :continue, fun2, parent, debug)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    exception = Core.UncaughtThrowError.exception([actual: :thrown])
    assert { ^exception, stack } = reason
    assert { __MODULE__, _, _, _ } = hd(stack),
      "stacktrace not from __MODULE__"
    Process.flag(:trap_exit, trap)
    report = "** Core #{erl_inspect(pid)} is terminating\n" <>
      "** Module  == #{erl_inspect(__MODULE__)}\n" <>
      "** Process == #{erl_inspect(pid)}\n" <>
      "** Parent  == #{erl_inspect(self())}\n" <>
      "** Reason for termination == \n"<>
      "#{List.to_string(:io_lib.format('** ~p', [reason]))}\n\n"
    assert TestIO.binread() === report
  end

  test "uncaught exit after hibernate" do
    fun = fn(parent, debug) ->
      Core.init_ack()
      # send message to self to wake up immediately
      send(self(), :awaken)
      fun2 = fn(_parent, _debug) -> exit(:exited) end
      Core.hibernate(__MODULE__, :continue, fun2, parent, debug)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(__MODULE__, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    assert :exited = reason, "reason is not exited"
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "call to pid" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, from, :hello } ->
          Core.reply(from, :hi)
      end
      close()
    end
    pid = Core.spawn_link(__MODULE__, fun)
    assert :hi === Core.call(pid, __MODULE__, :hello, 1000)
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to local name" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, from, :hello } ->
          Core.reply(from, :hi)
      end
      close()
    end
    { :ok, pid } = Core.start_link(__MODULE__, fun, local: :call_local)
    assert :hi === Core.call(:call_local, __MODULE__, :hello, 1000)
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to local name with local node" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, from, :hello } ->
          Core.reply(from, :hi)
      end
      close()
    end
    { :ok, pid } = Core.start_link(__MODULE__, fun, local: :call_local2)
    assert :hi === Core.call({ :call_local2, node() }, __MODULE__, :hello, 1000)
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to global name" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, from, :hello } ->
          Core.reply(from, :hi)
      end
      close()
    end
    name = { :global, :call_global }
    { :ok, pid } = Core.start_link(__MODULE__, fun, [name])
    assert :hi === Core.call(name, __MODULE__, :hello, 1000)
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to via name" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, from, :hello } ->
          Core.reply(from, :hi)
      end
      close()
    end
    name = { :via, :global, :call_via }
    { :ok, pid } = Core.start_link(__MODULE__, fun, via: { :global, :call_via })
    assert :hi === Core.call(name, __MODULE__, :hello, 1000)
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to pid and timeout" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, _from, :hello } ->
          nil
      end
      close()
    end
    pid = Core.spawn_link(__MODULE__, fun)
    assert catch_exit(Core.call(pid, __MODULE__, :hello, 100))
      == {:timeout, {Core, :call, [pid, __MODULE__, :hello, 100]}}
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to pid that is already dead" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      close()
    end
    pid = Core.spawn_link(__MODULE__, fun)
    close(pid)
    assert catch_exit(Core.call(pid, __MODULE__, :hello, 500))
      == {:noproc, {Core, :call, [pid, __MODULE__, :hello, 500]}}
   assert TestIO.binread() === <<>>
  end

  test "call to pid that exits" do
    fun = fn(_parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, _from, :hello } ->
          exit(:normal)
      end
    end
    pid = Core.spawn_link(__MODULE__, fun)
    assert catch_exit(Core.call(pid, __MODULE__, :hello, 500))
      == {:normal, {Core, :call, [pid, __MODULE__, :hello, 500]}}
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to local name that is not registered" do
    assert catch_exit(Core.call(:call_bad_local, __MODULE__, :hello, 500))
      == {:noproc, {Core, :call, [:call_bad_local, __MODULE__, :hello, 500]}}
  end

  test "call to local name with local node that is not registered" do
    assert catch_exit(Core.call({:call_bad_local, node()}, __MODULE__, :hello, 500))
      == {:noproc,
        {Core, :call, [{:call_bad_local, node()}, __MODULE__, :hello, 500]}}
  end

  test "call to global name that is not registered" do
    assert catch_exit(Core.call({:global, :call_bad_global}, __MODULE__, :hello, 500))
      == {:noproc,
        {Core, :call, [{:global, :call_bad_global}, __MODULE__, :hello, 500]}}
  end

  test "call to via name that is not registered" do
    assert catch_exit(Core.call({:via, :global, :call_bad_via}, __MODULE__, :hello, 500))
      == {:noproc,
        {Core, :call, [{:via, :global, :call_bad_via}, __MODULE__, :hello, 500]}}
  end

  test "call to local name on bad node" do
    assert catch_exit(Core.call({:call_bad_local, :node_does_not_exist}, __MODULE__, :hello, 500))
      == {{:nodedown, :node_does_not_exist},
        {Core, :call, [{:call_bad_local, :node_does_not_exist}, __MODULE__, :hello, 500]}}
  end

  test "cast to pid" do
    fun = fn(parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          send(parent,  { :hi, self() })
      end
      close()
    end
    pid = Core.spawn_link(__MODULE__, fun)
    assert :ok === Core.cast(pid, __MODULE__, :hello)
    assert_receive { :hi, ^pid }, 200, "cast was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "cast to local name" do
    fun = fn(parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          send(parent,  { :hi, self() })
      end
      close()
    end
    { :ok, pid } = Core.start_link(__MODULE__, fun, local: :cast_local)
    assert :ok === Core.cast(:cast_local, __MODULE__, :hello)
    assert_receive { :hi, ^pid }, 200, "cast was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "cast to local name with local node" do
    fun = fn(parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          send(parent,  { :hi, self() })
      end
      close()
    end
    { :ok, pid } = Core.start_link(__MODULE__, fun, local: :cast_local2)
    assert :ok === Core.cast({ :cast_local2, node() }, __MODULE__, :hello)
    assert_receive { :hi, ^pid }, 200, "cast was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "cast to global name" do
    fun = fn(parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          send(parent,  { :hi, self() })
      end
     close()
    end
    name = { :global, :cast_global }
    { :ok, pid } = Core.start_link(__MODULE__, fun, [name])
    assert :ok === Core.cast(name, __MODULE__, :hello)
    assert_receive { :hi, ^pid }, 200, "cast was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "cast to via name" do
    fun = fn(parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          send(parent,  { :hi, self() })
      end
      close()
    end
    name = { :via, :global, :cast_via }
    { :ok, pid } = Core.start_link(__MODULE__, fun, via: { :global, :cast_via })
    assert :ok === Core.cast(name, __MODULE__, :hello)
    assert_receive { :hi, ^pid }, 200, "cast was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "cast to local name that is not registered" do
    assert :ok === Core.cast(:cast_bad_local, __MODULE__, :hello)
  end

  test "cast to global name that is not registered" do
    assert :ok === Core.cast({ :global, :cast_bad_global }, __MODULE__, :hello)
  end

  test "cast to via name that is not registered" do
    assert :ok === Core.cast({ :via, :global, :cast_bad_via }, __MODULE__,
      :hello)
  end

  test "cast to local name on bad node" do
    assert :ok === Core.cast({ :cast_bad_local, :node_does_not_exist },
      __MODULE__, :hello)
  end

  test "send to pid" do
    fun = fn(parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          send(parent,  { :hi, self() })
      end
      close()
    end
    pid = Core.spawn_link(__MODULE__, fun)
    assert { __MODULE__, :hello } === Core.send(pid, {  __MODULE__, :hello })
    assert_receive { :hi, ^pid }, 200, "message was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "send to local name" do
    fun = fn(parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          send(parent,  { :hi, self() })
      end
      close()
    end
    { :ok, pid } = Core.start_link(__MODULE__, fun, local: :send_local)
    assert { __MODULE__, :hello } === Core.send(:send_local,
      { __MODULE__, :hello })
    assert_receive { :hi, ^pid }, 200, "message was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "send to local name with local node" do
    fun = fn(parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          send(parent,  { :hi, self() })
      end
      close()
    end
    { :ok, pid } = Core.start_link(__MODULE__, fun, local: :send_local2)
    assert { __MODULE__, :hello}  === Core.send({ :send_local2, node() },
      { __MODULE__, :hello })
    assert_receive { :hi, ^pid }, 200, "message was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "send to global name" do
    fun = fn(parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          send(parent,  { :hi, self() })
      end
     close()
    end
    name = { :global, :send_global }
    { :ok, pid } = Core.start_link(__MODULE__, fun, [name])
    assert { __MODULE__, :hello } === Core.send(name,{ __MODULE__, :hello })
    assert_receive { :hi, ^pid }, 200, "message was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "send to via name" do
    fun = fn(parent, _debug) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          send(parent,  { :hi, self() })
      end
      close()
    end
    name = { :via, :global, :send_via }
    { :ok, pid } = Core.start_link(__MODULE__, fun, via: { :global, :send_via })
    assert { __MODULE__, :hello }  === Core.send(name, { __MODULE__, :hello })
    assert_receive { :hi, ^pid }, 200, "message was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "send to local name that is not registered" do
    assert_raise ArgumentError,
      "no process associated with send_bad_local",
      fn() -> Core.send(:send_bad_local, { __MODULE__, :hello }) end
  end

  test "send to local name with local node that is not registered" do
    assert_raise ArgumentError,
      "no process associated with send_bad_local",
      fn() -> Core.send({ :send_bad_local, node() }, { __MODULE__, :hello }) end
  end

  test "send to global name that is not registered" do
    assert_raise ArgumentError,
      "no process associated with :send_bad_global (global)",
      fn() ->
        Core.send({ :global, :send_bad_global }, { __MODULE__, :hello })
      end
  end

  test "send to via name that is not registered" do
    assert_raise ArgumentError,
      "no process associated with :send_bad_via (global)",
      fn() ->
        Core.send({ :via, :global, :send_bad_via }, { __MODULE__, :hello })
      end
  end

  ## utils

  defp linked?(pid) do
    { :links, links } = Process.info(self(), :links)
    Enum.member?(links, pid)
  end

  defp close(pid) do
    ref = Process.monitor(pid)
    Process.unlink(pid)
    send(pid, :close)
    receive do
      { :DOWN, ^ref, _, _, reason } ->
        reason
    after
      500 ->
        Process.demonitor(ref, [:flush])
        Process.exit(pid, :kill)
        :timeout
    end
  end

  defp close() do
    receive do
      :close ->
        exit(:normal)
    after
      500 ->
        exit(:timeout)
    end
  end

  defp erl_inspect(term) do
    List.to_string(:io_lib.format('~p', [term]))
  end

end
