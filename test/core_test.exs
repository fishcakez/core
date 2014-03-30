Code.require_file "test_helper.exs", __DIR__

defmodule CoreTest do
  use ExUnit.Case

  use Core.Behaviour

  def init(parent, fun) do
      fun.(parent)
  end

  def continue(fun, parent) do
    fun.(parent)
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
    fun = fn(parent) ->
      Core.init_ack()
      Process.send(starter, { :parent, parent })
      close()
    end
    assert { :ok, pid } = Core.start_link(CoreTest, fun)
    assert_receive { :parent, ^starter }, 200, "parent not starter"
    assert linked?(pid), "child not linked"
    assert :normal === close(pid), "close failed"
    assert TestIO.binread() === <<>>
  end

  test "start_link with timeout" do
    fun = fn(_parent) ->
      :timer.sleep(5000)
    end
    assert { :error, :timeout } = Core.start_link(nil, CoreTest, fun,
      [{ :timeout, 1 }]), "didn't timeout"
    assert TestIO.binread() === <<>>
  end

  test "start_link with init_ignore" do
    fun = fn(_parent) ->
      Core.init_ignore()
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, true)
    assert :ignore === Core.start_link(CoreTest, fun)
    assert_receive { :EXIT, _child, :normal }, 200, "init_ignore did not exit"
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
 end

  test "start_link with init_ack/1" do
    fun = fn(_parent) ->
      Core.init_ack(:extra_data)
      close()
    end
    assert { :ok, pid, :extra_data } = Core.start_link(CoreTest, fun)
    assert close(pid) === :normal, "close failed"
    assert TestIO.binread() === <<>>
  end

  test "start_link with init_stop" do
    fun = fn(parent) ->
      Core.init_stop(__MODULE__, parent, nil, :init_error)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    assert { :error, :init_error } = Core.start_link(CoreTest, fun)
    assert_receive { :EXIT, _pid, :init_error }, 200, "init_stop did not exit"
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "start_link register local name" do
    fun = fn(_parent) ->
      Core.init_ack()
      close()
    end
    name = :base_start_link
    assert { :ok, pid1 } = Core.start_link(name, CoreTest, fun)
    assert Core.whereis(name) === pid1
    trap = Process.flag(:trap_exit, true)
    assert { :error, { :already_started, ^pid1 } } = Core.start_link(name,
      CoreTest, fun)
    assert_receive { :EXIT, _pid2, :normal }, 200,
      "already started did not exit normally"
    Process.flag(:trap_exit, trap)
    assert close(pid1) === :normal
    assert TestIO.binread() === <<>>
  end

  test "start_link register global name" do
    fun = fn(_parent) ->
      Core.init_ack()
      close()
    end
    name = { :global, :base_start_link }
    assert { :ok, pid1 } = Core.start_link(name, CoreTest, fun)
    assert Core.whereis(name) === pid1
    trap = Process.flag(:trap_exit, true)
    assert { :error, { :already_started, ^pid1 } } = Core.start_link(name,
      CoreTest, fun)
    assert_receive { :EXIT, _pid2, :normal }, 200,
      "already started did not exit normally"
    Process.flag(:trap_exit, trap)
    assert close(pid1) === :normal
    assert TestIO.binread() === <<>>
  end

  test "start_link register via name" do
    fun = fn(_parent) ->
      Core.init_ack()
      close()
    end
    name = { :via, :global, :base_start_link_via }
    assert { :ok, pid1 } = Core.start_link(name, CoreTest, fun)
    assert Core.whereis(name) === pid1
    trap = Process.flag(:trap_exit, true)
    assert { :error, { :already_started, ^pid1 } } = Core.start_link(name,
      CoreTest, fun)
    assert_receive { :EXIT, _pid2, :normal }, 200,
      "already started did not exit normally"
    Process.flag(:trap_exit, trap)
    assert close(pid1) === :normal
    assert TestIO.binread() === <<>>
  end

  test "start with init_ack/0" do
    starter = self()
    fun = fn(parent) ->
      Core.init_ack()
      Process.send(starter, { :parent, parent })
      close()
    end
    assert { :ok, pid } = Core.start(CoreTest, fun)
    assert_receive { :parent, ^pid }, 200, "parent not self()"
    refute linked?(pid), "child linked"
    assert close(pid) === :normal, "close failed"
    assert TestIO.binread() === <<>>
  end

  test "start with timeout" do
    fun = fn(_parent) ->
      :timer.sleep(5000)
    end
    assert { :error, :timeout } = Core.start(nil, CoreTest, fun,
      [{ :timeout, 1 }]), "didn't timeout"
    assert TestIO.binread() === <<>>
  end


  test "start register local name" do
    fun = fn(_parent) ->
      Core.init_ack()
      close()
    end
    name = :base_start
    assert { :ok, pid1 } = Core.start(name, CoreTest, fun)
    assert Core.whereis(name) === pid1
    assert { :error, { :already_started, ^pid1 } } = Core.start_link(name,
      CoreTest, fun)
    assert close(pid1) === :normal
    assert TestIO.binread() === <<>>
  end

  test "start with link" do
    starter = self()
    fun = fn(parent) ->
      Process.send(starter, { :parent, parent })
      Core.init_ack()
      close()
    end
    assert { :ok, pid } = Core.start(nil, CoreTest, fun, [{ :spawn, [:link] }])
    assert_received { :parent, ^pid }, "parent not self()"
    assert linked?(pid), "child not linked"
    assert :normal === close(pid), "close failed"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link with init_ack/0" do
    starter = self()
    fun = fn(parent) ->
      Core.init_ack()
      Process.send(starter, { :parent, parent })
      close()
    end
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :parent, ^starter }, 200, "parent not starter"
    assert linked?(pid), "child not linked"
    assert close(pid) === :normal, "close failed"
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link with init_ignore" do
    fun = fn(_parent) ->
      Core.init_ignore()
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, :normal }, 200, "init_ignore did not exit"
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
 end

  test "spawn_link with init_ack/1" do
    fun = fn(_parent) ->
      Core.init_ack(:extra_data)
      close()
    end
    pid = Core.spawn_link(CoreTest, fun)
    assert close(pid) === :normal, "close failed"
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link with init_stop" do
    fun = fn(parent) ->
      Core.init_stop(__MODULE__, parent, nil, :init_error)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, :init_error }, 200, "init_stop did not exit"
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    report = "** #{inspect(__MODULE__)} #{inspect(pid)} is terminating\n" <>
      "   Arguments: nil\n" <>
      "   Pid: #{inspect(pid)}\n" <>
      "   Parent: #{inspect(self())}\n" <>
      "   Last Event: nil\n" <>
      "   EXIT: :init_error\n" <>
      "\n"
    assert TestIO.binread() === report
  end

  test "spawn_link with exception and stack init_stop" do
    exception = ArgumentError[message: "hello"]
    stack = try do
      throw(:hi)
    catch
      :hi ->
        System.stacktrace()
    end
    fun = fn(parent) ->
      Core.init_stop(__MODULE__, parent, nil, { exception, stack })
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "init_stop did not exit"
    assert reason === { exception, stack }
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    report = "** #{inspect(__MODULE__)} #{inspect(pid)} is raising an exception\n" <>
      "   Arguments: nil\n" <>
      "   Pid: #{inspect(pid)}\n" <>
      "   Parent: #{inspect(self())}\n" <>
      "   Last Event: nil\n" <>
      "   (ArgumentError) hello\n" <>
      Exception.format_stacktrace(stack) <>
      "\n"
    assert TestIO.binread() === report
  end

  test "spawn_link with exception and nil stack init_stop" do
    exception = ArgumentError[message: "hello"]
    fun = fn(parent) ->
      Core.init_stop(__MODULE__, parent, nil, { exception, nil })
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "init_stop did not exit"
    assert { ^exception, nil } = reason
      "stacktrace not from init_stop"
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    report = "** #{inspect(__MODULE__)} #{inspect(pid)} is terminating\n" <>
      "   Arguments: nil\n" <>
      "   Pid: #{inspect(pid)}\n" <>
      "   Parent: #{inspect(self())}\n" <>
      "   Last Event: nil\n" <>
      "   EXIT: #{inspect({ exception, nil })}\n" <>
      "\n"
    assert TestIO.binread() === report
  end

  test "spawn_link with normal init_stop" do
    fun = fn(parent) ->
      event = :test_event
      Core.init_stop(__MODULE__, parent, nil, :normal, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "init_stop did not exit"
    assert reason === :normal
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link with shutdown init_stop" do
    fun = fn(parent) ->
      event = :test_event
      Core.init_stop(__MODULE__, parent, nil, :shutdown, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "init_stop did not exit"
    assert reason === :shutdown
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link with shutdown term init_stop" do
    fun = fn(parent) ->
      event = :test_event
      Core.init_stop(__MODULE__, parent, nil, { :shutdown, nil }, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "init_stop did not exit"
    assert reason === { :shutdown, nil }
    Process.flag(:trap_exit, trap)
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn_link register local name" do
    starter = self()
    fun = fn(_parent) ->
      Process.send(starter, { :registered, self() })
      Core.init_ack()
      close()
    end
    name = :base_spawn_link
    assert pid1 = Core.spawn_link(name, CoreTest, fun)
    assert_receive { :registered, ^pid1 }, 200, "did not register"
    assert Core.whereis(name) === pid1
    assert pid2 = Core.spawn_link(name, CoreTest, fun)
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
    fun = fn(parent) ->
      Core.init_ack()
      Process.send(starter, { :parent, parent })
      close()
    end
    pid = Core.spawn(CoreTest, fun)
    assert_receive { :parent, ^pid }, 200, "parent not self()"
    refute linked?(pid), "child linked"
    assert close(pid) === :normal, "close failed"
    refute_received { :ack, ^pid, _ }, "init_ack sent"
    assert TestIO.binread() === <<>>
  end

  test "spawn register local name" do
    starter = self()
    fun = fn(_parent) ->
      Process.send(starter, { :registered, self() })
      Core.init_ack()
      close()
    end
    name = :base_spawn
    assert pid1 = Core.spawn(name, CoreTest, fun)
    assert_receive { :registered, ^pid1 }, 200, "did not register"
    assert Core.whereis(name) === pid1
    assert pid2 = Core.spawn(name, CoreTest, fun)
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
    fun = fn(_parent) ->
      Core.init_ack()
      close()
    end
    pid = Core.spawn(nil, CoreTest, fun, [{ :spawn, [:link] }])
    assert linked?(pid), "child not linked"
    assert :normal === close(pid), "close failed"
    assert TestIO.binread() === <<>>
  end

  test "stop" do
    fun = fn(parent) ->
      Core.init_ack()
      Core.stop(__MODULE__, nil, parent, :error)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, :error }, 200, "stop did not exit"
    Process.flag(:trap_exit, trap)
    report = "** #{inspect(__MODULE__)} #{inspect(pid)} is terminating\n" <>
      "   State: nil\n" <>
      "   Pid: #{inspect(pid)}\n" <>
      "   Parent: #{inspect(self())}\n" <>
      "   Last Event: nil\n" <>
      "   EXIT: :error\n" <>
      "\n"
    assert TestIO.binread() === report
  end

  test "stop with exception and stack" do
    exception = ArgumentError[message: "hello"]
    stack = try do
      throw(:hi)
    catch
      :hi ->
        System.stacktrace()
    end
    fun = fn(parent) ->
      Core.init_ack()
      Core.stop(__MODULE__, nil, parent, { exception, stack })
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "stop did not exit"
    assert reason === { exception, stack }
    Process.flag(:trap_exit, trap)
    report = "** #{inspect(__MODULE__)} #{inspect(pid)} is raising an exception\n" <>
      "   State: nil\n" <>
      "   Pid: #{inspect(pid)}\n" <>
      "   Parent: #{inspect(self())}\n" <>
      "   Last Event: nil\n" <>
      "   (ArgumentError) hello\n" <>
      Exception.format_stacktrace(stack) <>
      "\n"
    assert TestIO.binread() === report
  end

  test "stop with exception and nil stack" do
    exception = ArgumentError[message: "hello"]
    fun = fn(parent) ->
      Core.init_ack()
      Core.stop(__MODULE__, nil, parent, { exception, nil })
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "stop did not exit"
    assert { ^exception, nil } = reason
    Process.flag(:trap_exit, trap)
    report = "** #{inspect(__MODULE__)} #{inspect(pid)} is terminating\n" <>
      "   State: nil\n" <>
      "   Pid: #{inspect(pid)}\n" <>
      "   Parent: #{inspect(self())}\n" <>
      "   Last Event: nil\n" <>
      "   EXIT: #{inspect({ exception, nil })}\n" <>
      "\n"
    assert TestIO.binread() === report
  end
  test "stop with normal" do
    fun = fn(parent) ->
      Core.init_ack()
      event = :test_event
      Core.stop(__MODULE__, nil, parent, :normal, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "stop did not exit"
    assert reason === :normal
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "stop with shutdown" do
    fun = fn(parent) ->
      Core.init_ack()
      event = :test_event
      Core.stop(__MODULE__, nil, parent, :shutdown, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "stop did not exit"
    assert reason === :shutdown
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "stop with shutdown term" do
    fun = fn(parent) ->
      Core.init_ack()
      event = :test_event
      Core.stop(__MODULE__, nil, parent, { :shutdown, nil }, event)
      :timer.sleep(5000)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "stop did not exit"
    assert reason === { :shutdown, nil }
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "uncaught exception" do
    exception = ArgumentError[message: "hello"]
    fun = fn(_parent) ->
      Core.init_ack()
      raise exception, []
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    assert { ^exception, stack } = reason
    assert { __MODULE__, _, _, _ } = hd(stack),
      "stacktrace not from __MODULE__"
    Process.flag(:trap_exit, trap)
    report = "** Core #{inspect(pid)} is raising an exception\n" <>
      "   Module: #{inspect(__MODULE__)}\n" <>
      "   Pid: #{inspect(pid)}\n" <>
      "   Parent: #{inspect(self())}\n" <>
      "   (ArgumentError) hello\n" <>
      Exception.format_stacktrace(stack) <>
      "\n"
    assert TestIO.binread() === report
  end

  test "uncaught throw" do
    fun = fn(_parent) ->
      Core.init_ack()
      throw(:thrown)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    exception = Core.UncaughtThrowError[actual: :thrown]
    assert { ^exception, stack } = reason
    assert { __MODULE__, _, _, _ } = hd(stack),
      "stacktrace not from __MODULE__"
    Process.flag(:trap_exit, trap)
    report = "** Core #{inspect(pid)} is raising an exception\n" <>
      "   Module: #{inspect(__MODULE__)}\n" <>
      "   Pid: #{inspect(pid)}\n" <>
      "   Parent: #{inspect(self())}\n" <>
      "   (Core.UncaughtThrowError) uncaught throw: :thrown\n" <>
      Exception.format_stacktrace(stack) <>
      "\n"
    assert TestIO.binread() === report
  end

  test "uncaught exit" do
    fun = fn(_parent) ->
      Core.init_ack()
      exit(:exited)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    assert :exited = reason, "reason is not exited"
    Process.flag(:trap_exit, trap)
     assert TestIO.binread() === <<>>
  end

  test "uncaught exception after hibernate" do
    exception = ArgumentError[message: "hello"]
    fun = fn(parent) ->
      Core.init_ack()
      # send message to self to wake up immediately
      Process.send(self(), :awaken)
      fun2 = fn(_parent) -> raise ArgumentError, [message: "hello"] end
      Core.hibernate(__MODULE__, :continue, fun2, parent)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    assert { ^exception, stack } = reason
    assert { __MODULE__, _, _, _ } = hd(stack),
      "stacktrace not from __MODULE__"
    Process.flag(:trap_exit, trap)
    report = "** Core #{inspect(pid)} is raising an exception\n" <>
      "   Module: #{inspect(__MODULE__)}\n" <>
      "   Pid: #{inspect(pid)}\n" <>
      "   Parent: #{inspect(self())}\n" <>
      "   (ArgumentError) hello\n" <>
      Exception.format_stacktrace(stack) <>
      "\n"
    assert TestIO.binread() === report
  end

  test "uncaught throw after hibernate" do
    fun = fn(parent) ->
      Core.init_ack()
      # send message to self to wake up immediately
      Process.send(self(), :awaken)
      fun2 = fn(_parent) -> throw(:thrown) end
      Core.hibernate(__MODULE__, :continue, fun2, parent)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    exception = Core.UncaughtThrowError[actual: :thrown]
    assert { ^exception, stack } = reason
    assert { __MODULE__, _, _, _ } = hd(stack),
      "stacktrace not from __MODULE__"
    Process.flag(:trap_exit, trap)
    report = "** Core #{inspect(pid)} is raising an exception\n" <>
      "   Module: #{inspect(__MODULE__)}\n" <>
      "   Pid: #{inspect(pid)}\n" <>
      "   Parent: #{inspect(self())}\n" <>
      "   (Core.UncaughtThrowError) uncaught throw: :thrown\n" <>
      Exception.format_stacktrace(stack) <>
      "\n"
    assert TestIO.binread() === report
  end

  test "uncaught exit after hibernate" do
    fun = fn(parent) ->
      Core.init_ack()
      # send message to self to wake up immediately
      Process.send(self(), :awaken)
      fun2 = fn(_parent) -> exit(:exited) end
      Core.hibernate(__MODULE__, :continue, fun2, parent)
    end
    trap = Process.flag(:trap_exit, :true)
    pid = Core.spawn_link(CoreTest, fun)
    assert_receive { :EXIT, ^pid, reason }, 200, "child did not exit"
    assert :exited = reason, "reason is not exited"
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "call to pid" do
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, from, :hello } ->
          Core.reply(from, :hi)
      end
      close()
    end
    pid = Core.spawn_link(CoreTest, fun)
    assert :hi === Core.call(pid, __MODULE__, :hello, 1000)
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to local name" do
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, from, :hello } ->
          Core.reply(from, :hi)
      end
      close()
    end
    { :ok, pid } = Core.start_link(:call_local, CoreTest, fun)
    assert :hi === Core.call(:call_local, __MODULE__, :hello, 1000)
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to local name with local node" do
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, from, :hello } ->
          Core.reply(from, :hi)
      end
      close()
    end
    { :ok, pid } = Core.start_link(:call_local2, CoreTest, fun)
    assert :hi === Core.call({ :call_local2, node() }, __MODULE__, :hello, 1000)
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to global name" do
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, from, :hello } ->
          Core.reply(from, :hi)
      end
      close()
    end
    name = { :global, :call_global }
    { :ok, pid } = Core.start_link(name, CoreTest, fun)
    assert :hi === Core.call(name, __MODULE__, :hello, 1000)
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to via name" do
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, from, :hello } ->
          Core.reply(from, :hi)
      end
      close()
    end
    name = { :via, :global, :call_via }
    { :ok, pid } = Core.start_link(name, CoreTest, fun)
    assert :hi === Core.call(name, __MODULE__, :hello, 1000)
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to pid and timeout" do
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, _from, :hello } ->
          nil
      end
      close()
    end
    pid = Core.spawn_link(CoreTest, fun)
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to #{inspect(pid)} failed: " <>
      "#{inspect(pid)} did not respond in time",
      fn() -> Core.call(pid, __MODULE__, :hello, 100) end
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to pid that is already dead" do
    fun = fn(_parent) ->
      Core.init_ack()
      close()
    end
    pid = Core.spawn_link(CoreTest, fun)
    close(pid)
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to #{inspect(pid)} failed: " <>
      "#{inspect(pid)} is not alive",
      fn() -> Core.call(pid, __MODULE__, :hello, 500) end
    assert TestIO.binread() === <<>>
  end

  test "call to pid that exits normally" do
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, _from, :hello } ->
          exit(:normal)
      end
    end
    pid = Core.spawn_link(CoreTest, fun)
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to #{inspect(pid)} failed: " <>
      "#{inspect(pid)} exited normally",
      fn() -> Core.call(pid, __MODULE__, :hello, 500) end
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "call to pid that shuts down" do
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, _from, :hello } ->
          exit(:shutdown)
      end
    end
    pid = Core.spawn_link(CoreTest, fun)
    trap = Process.flag(:trap_exit, true)
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to #{inspect(pid)} failed: " <>
      "#{inspect(pid)} shutdown",
      fn() -> Core.call(pid, __MODULE__, :hello, 500) end
    assert_receive { :EXIT, ^pid, :shutdown }
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "call to pid that shuts down with term" do
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, _from, :hello } ->
          exit({ :shutdown, nil })
      end
    end
    pid = Core.spawn_link(CoreTest, fun)
    trap = Process.flag(:trap_exit, true)
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to #{inspect(pid)} failed: " <>
      "#{inspect(pid)} shutdown with reason: nil",
      fn() -> Core.call(pid, __MODULE__, :hello, 500) end
    assert_receive { :EXIT, ^pid, { :shutdown, nil } }
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "call to pid that raises an exception" do
    exception = ArgumentError[message: "hello"]
    stack = try do
      throw(:stacktrace)
    catch
      :stacktrace ->
        System.stacktrace()
    end
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, _from, :hello } ->
          # this will look like exception was raised with stack
          exit({ exception, stack })
      end
    end
    pid = Core.spawn_link(CoreTest, fun)
    trap = Process.flag(:trap_exit, true)
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to #{inspect(pid)} failed: " <>
      "#{inspect(pid)} raised an exception\n" <>
      "   (ArgumentError) hello\n" <>
      Exception.format_stacktrace(stack),
      fn() -> Core.call(pid, __MODULE__, :hello, 500) end
    assert_receive { :EXIT, ^pid, { ^exception, ^stack } }
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "call to pid that exits with exception and nil stack" do
    exception = ArgumentError[message: "hello"]
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, _from, :hello } ->
          # this looks like an exception and Exception.stacktrace will provide
          # a generated stacktrace in the place of nil
          exit({ exception, nil })
      end
    end
    pid = Core.spawn_link(CoreTest, fun)
    trap = Process.flag(:trap_exit, true)
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to #{inspect(pid)} failed: " <>
      "#{inspect(pid)} exited with reason: #{inspect({ exception, nil })}",
      fn() -> Core.call(pid, __MODULE__, :hello, 500) end
    assert_receive { :EXIT, ^pid, { ^exception, nil } }
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "call to pid that is killed" do
    fun = fn(_parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, _from, :hello } ->
          Process.exit(self(), :kill)
      end
    end
    pid = Core.spawn_link(CoreTest, fun)
    trap = Process.flag(:trap_exit, true)
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to #{inspect(pid)} failed: " <>
      "#{inspect(pid)} was killed",
      fn() -> Core.call(pid, __MODULE__, :hello, 500) end
    assert_receive { :EXIT, ^pid, :killed }
    Process.flag(:trap_exit, trap)
    assert TestIO.binread() === <<>>
  end

  test "call to local name that is not registered" do
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to call_bad_local failed: " <>
      "no process associated with that name",
      fn() -> Core.call(:call_bad_local, __MODULE__, :hello, 500) end
  end

  test "call to local name with local node that is not registered" do
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to call_bad_local failed: " <>
      "no process associated with that name",
      fn() ->
        Core.call({ :call_bad_local, node() }, __MODULE__, :hello, 500)
      end
  end

  test "call to global name that is not registered" do
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to :call_bad_global (global) failed: " <>
      "no process associated with that name",
      fn() ->
        Core.call({ :global, :call_bad_global }, __MODULE__, :hello, 500)
      end
  end

  test "call to via name that is not registered" do
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to :call_bad_via (global) failed: " <>
      "no process associated with that name",
      fn() ->
        Core.call({ :via, :global, :call_bad_via }, __MODULE__, :hello, 500)
      end
  end

  test "call to local name on bad node" do
    assert_raise Core.CallError,
      "#{inspect(__MODULE__)} :hello to " <>
      "call_bad_local on node_does_not_exist failed: " <>
      "call_bad_local on node_does_not_exist is disconnected",
      fn() ->
        Core.call({ :call_bad_local, :node_does_not_exist }, __MODULE__, :hello,
          500)
      end
  end

  test "cast to pid" do
    fun = fn(parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          Process.send(parent,  { :hi, self() })
      end
      close()
    end
    pid = Core.spawn_link(CoreTest, fun)
    assert :ok === Core.cast(pid, __MODULE__, :hello)
    assert_receive { :hi, ^pid }, 200, "cast was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "cast to local name" do
    fun = fn(parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          Process.send(parent,  { :hi, self() })
      end
      close()
    end
    { :ok, pid } = Core.start_link(:cast_local, CoreTest, fun)
    assert :ok === Core.cast(:cast_local, __MODULE__, :hello)
    assert_receive { :hi, ^pid }, 200, "cast was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "cast to local name with local node" do
    fun = fn(parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          Process.send(parent,  { :hi, self() })
      end
      close()
    end
    { :ok, pid } = Core.start_link(:cast_local2, CoreTest, fun)
    assert :ok === Core.cast({ :cast_local2, node() }, __MODULE__, :hello)
    assert_receive { :hi, ^pid }, 200, "cast was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "cast to global name" do
    fun = fn(parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          Process.send(parent,  { :hi, self() })
      end
     close()
    end
    name = { :global, :cast_global }
    { :ok, pid } = Core.start_link(name, CoreTest, fun)
    assert :ok === Core.cast(name, __MODULE__, :hello)
    assert_receive { :hi, ^pid }, 200, "cast was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "cast to via name" do
    fun = fn(parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          Process.send(parent,  { :hi, self() })
      end
      close()
    end
    name = { :via, :global, :cast_via }
    { :ok, pid } = Core.start_link(name, CoreTest, fun)
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
    fun = fn(parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          Process.send(parent,  { :hi, self() })
      end
      close()
    end
    pid = Core.spawn_link(CoreTest, fun)
    assert { __MODULE__, :hello } === Core.send(pid, {  __MODULE__, :hello })
    assert_receive { :hi, ^pid }, 200, "message was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "send to local name" do
    fun = fn(parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          Process.send(parent,  { :hi, self() })
      end
      close()
    end
    { :ok, pid } = Core.start_link(:send_local, CoreTest, fun)
    assert { __MODULE__, :hello } === Core.send(:send_local,
      { __MODULE__, :hello })
    assert_receive { :hi, ^pid }, 200, "message was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "send to local name with local node" do
    fun = fn(parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          Process.send(parent,  { :hi, self() })
      end
      close()
    end
    { :ok, pid } = Core.start_link(:send_local2, CoreTest, fun)
    assert { __MODULE__, :hello}  === Core.send({ :send_local2, node() },
      { __MODULE__, :hello })
    assert_receive { :hi, ^pid }, 200, "message was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "send to global name" do
    fun = fn(parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          Process.send(parent,  { :hi, self() })
      end
     close()
    end
    name = { :global, :send_global }
    { :ok, pid } = Core.start_link(name, CoreTest, fun)
    assert { __MODULE__, :hello } === Core.send(name,{ __MODULE__, :hello })
    assert_receive { :hi, ^pid }, 200, "message was not received"
    close(pid)
    assert TestIO.binread() === <<>>
  end

  test "send to via name" do
    fun = fn(parent) ->
      Core.init_ack()
      receive do
        { __MODULE__, :hello } ->
          Process.send(parent,  { :hi, self() })
      end
      close()
    end
    name = { :via, :global, :send_via }
    { :ok, pid } = Core.start_link(name, CoreTest, fun)
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
    Process.send(pid, :close)
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

end
