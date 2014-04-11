Code.require_file "../test_helper.exs", __DIR__

defmodule Core.DebugTest do
  use ExUnit.Case

  require Core.Debug

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

  test "get/set default options" do
    assert Core.Debug.set_opts([{ :log, 10 }, { :stats, true }]) === :ok
    assert [{ :log, 10}, {:stats, true }] == Core.Debug.get_opts()
    assert Core.Debug.set_opts([{ :log, 10 }]) === :ok
    assert [{ :log, 10 }] = Core.Debug.get_opts()
    assert Core.Debug.set_opts([]) === :ok
  end

  test "log with 2 events and get log" do
    debug = Core.Debug.new([{ :log, 10 }])
    debug = Core.Debug.event(debug, { :event, 1 })
    debug = Core.Debug.event(debug, { :event, 2 })
    # order is important
    assert [{ :event, 1 }, { :event, 2 }] = Core.Debug.get_log(debug)
  end

  test "log with 0 events and get log" do
    debug = Core.Debug.new([{ :log, 10 }])
    assert Core.Debug.get_log(debug) === []
  end

  test "no log with 2 events and get log" do
    debug = Core.Debug.new([])
    debug = Core.Debug.event(debug, { :event, 1 })
    debug = Core.Debug.event(debug, { :event, 2 })
    assert Core.Debug.get_log(debug) === []
  end

  test "log with 2 events and print log" do
    debug = Core.Debug.new([{ :log, 10 }])
    debug = Core.Debug.event(debug, { :event, 1 })
    debug = Core.Debug.event(debug, { :event, 2 })
    assert Core.Debug.print_log(debug) === :ok
    report = "** Core.Debug #{inspect(self())} event log:\n" <>
    "** Core.Debug #{inspect(self())} #{inspect({ :event, 1 })}\n" <>
    "** Core.Debug #{inspect(self())} #{inspect({ :event, 2 })}\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "log with 0 events and print log" do
    debug = Core.Debug.new([{ :log, 10 }])
    assert Core.Debug.print_log(debug) === :ok
    report = "** Core.Debug #{inspect(self())} event log is empty\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "no log with 2 events and print log" do
    debug = Core.Debug.new([])
    debug = Core.Debug.event(debug, { :event, 1 })
    debug = Core.Debug.event(debug, { :event, 2 })
    assert Core.Debug.print_log(debug) === :ok
    report = "** Core.Debug #{inspect(self())} event log is empty\n\n"
    assert TestIO.binread() === report
  end

  test "log with cast message in and print log" do
    debug = Core.Debug.new([{ :log, 10 }])
    debug = Core.Debug.event(debug, { :in, :hello })
    assert Core.Debug.print_log(debug) === :ok
    report = "** Core.Debug #{inspect(self())} event log:\n" <>
    "** Core.Debug #{inspect(self())} message in: :hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "log with call message in and print log" do
    debug = Core.Debug.new([{ :log, 10 }])
    pid = spawn(fn() -> :ok end)
    debug = Core.Debug.event(debug, { :in, :hello, pid })
    assert Core.Debug.print_log(debug) === :ok
    report = "** Core.Debug #{inspect(self())} event log:\n" <>
    "** Core.Debug #{inspect(self())} " <>
    "message in (from #{inspect(pid)}): :hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "log with message out and print log" do
    debug = Core.Debug.new([{ :log, 10 }])
    pid = spawn(fn() -> :ok end)
    debug = Core.Debug.event(debug, { :out, :hello, pid })
    assert Core.Debug.print_log(debug) === :ok
    report = "** Core.Debug #{inspect(self())} event log:\n" <>
    "** Core.Debug #{inspect(self())} " <>
    "message out (to #{inspect(pid)}): :hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "stats with 0 events and get stats" do
    min_start = seconds()
    start_reductions = reductions()
    debug = Core.Debug.new([{ :stats, true }])
    assert stats = Core.Debug.get_stats(debug)
    max_reductions = reductions() - start_reductions
    max_current = seconds()
    assert stats[:in] === 0
    assert stats[:out] === 0
    assert stats[:reductions] < max_reductions
    assert seconds(stats[:start_time]) >= min_start
    assert seconds(stats[:current_time]) <= max_current
    assert Map.size(stats) === 5
  end

  test "stats with cast message in and get stats" do
    debug = Core.Debug.new([{ :stats, true }])
    debug = Core.Debug.event(debug, { :in, :hello })
    assert stats = Core.Debug.get_stats(debug)
    assert stats[:in] === 1
  end

  test "stats with call message in and get stats" do
    debug = Core.Debug.new([{ :stats, true }])
    debug = Core.Debug.event(debug, { :in, :hello, self() })
    assert stats = Core.Debug.get_stats(debug)
    assert stats[:in] === 1
  end

  test "stats with message out and get stats" do
    debug = Core.Debug.new([{ :stats, true }])
    debug = Core.Debug.event(debug, { :out, :hello, self() })
    assert stats = Core.Debug.get_stats(debug)
    assert stats[:out] === 1
  end

  test "stats with one of each event and print stats" do
    debug = Core.Debug.new([{ :stats, true }])
    debug = Core.Debug.event(debug, { :in, :hello, })
    debug = Core.Debug.event(debug, { :in, :hello, self() })
    debug = Core.Debug.event(debug, { :out, :hello, self() })
    assert Core.Debug.print_stats(debug) === :ok
    output = TestIO.binread()
    pattern = "\\A\\*\\* Core.Debug #{inspect(self())} statistics:\n" <>
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

  test "no stats and print stats" do
    debug = Core.Debug.new([])
    assert Core.Debug.print_stats(debug) === :ok
    report = "** Core.Debug #{inspect(self())} statistics not active\n" <>
    "\n"
    assert TestIO.binread() === report
  end



  ## utils

  defp seconds(datetime \\ :erlang.localtime()) do
    :calendar.datetime_to_gregorian_seconds(datetime)
  end

  defp reductions() do
    { :reductions, self_reductions } = Process.info(self(), :reductions)
    self_reductions
  end

end
