Code.require_file "../test_helper.exs", __DIR__

defmodule Base.DebugTest do
  use ExUnit.Case

  require Base.Debug

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
    assert Base.Debug.set_opts([{ :log, 10 }, { :stats, true }]) === :ok
    assert [{ :log, 10}, {:stats, true }] == Base.Debug.get_opts()
    assert Base.Debug.set_opts([{ :log, 10 }]) === :ok
    assert [{ :log, 10 }] = Base.Debug.get_opts()
    assert Base.Debug.set_opts([]) === :ok
  end

  test "log with 2 events and get log" do
    debug = Base.Debug.new([{ :log, 10 }])
    debug = Base.Debug.event(debug, { :event, 1 })
    debug = Base.Debug.event(debug, { :event, 2 })
    # order is important
    assert [{ :event, 1 }, { :event, 2 }] = Base.Debug.get_log(debug)
  end

  test "log with 0 events and get log" do
    debug = Base.Debug.new([{ :log, 10 }])
    assert Base.Debug.get_log(debug) === []
  end

  test "no log with 2 events and get log" do
    debug = Base.Debug.new([])
    debug = Base.Debug.event(debug, { :event, 1 })
    debug = Base.Debug.event(debug, { :event, 2 })
    assert Base.Debug.get_log(debug) === []
  end

  test "log with 2 events and print log" do
    debug = Base.Debug.new([{ :log, 10 }])
    debug = Base.Debug.event(debug, { :event, 1 })
    debug = Base.Debug.event(debug, { :event, 2 })
    assert Base.Debug.print_log(debug) === :ok
    report = "** Base.Debug #{inspect(self())} event log:\n" <>
    "** Base.Debug #{inspect(self())} #{inspect({ :event, 1 })}\n" <>
    "** Base.Debug #{inspect(self())} #{inspect({ :event, 2 })}\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "log with 0 events and print log" do
    debug = Base.Debug.new([{ :log, 10 }])
    assert Base.Debug.print_log(debug) === :ok
    report = "** Base.Debug #{inspect(self())} event log is empty\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "no log with 2 events and print log" do
    debug = Base.Debug.new([])
    debug = Base.Debug.event(debug, { :event, 1 })
    debug = Base.Debug.event(debug, { :event, 2 })
    assert Base.Debug.print_log(debug) === :ok
    report = "** Base.Debug #{inspect(self())} event log is empty\n\n"
    assert TestIO.binread() === report
  end

  test "log with cast message in and print log" do
    debug = Base.Debug.new([{ :log, 10 }])
    debug = Base.Debug.event(debug, { :in, :hello })
    assert Base.Debug.print_log(debug) === :ok
    report = "** Base.Debug #{inspect(self())} event log:\n" <>
    "** Base.Debug #{inspect(self())} message in: :hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "log with call message in and print log" do
    debug = Base.Debug.new([{ :log, 10 }])
    pid = spawn(fn() -> :ok end)
    debug = Base.Debug.event(debug, { :in, :hello, pid })
    assert Base.Debug.print_log(debug) === :ok
    report = "** Base.Debug #{inspect(self())} event log:\n" <>
    "** Base.Debug #{inspect(self())} " <>
    "message in (from #{inspect(pid)}): :hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "log with message out and print log" do
    debug = Base.Debug.new([{ :log, 10 }])
    pid = spawn(fn() -> :ok end)
    debug = Base.Debug.event(debug, { :out, :hello, pid })
    assert Base.Debug.print_log(debug) === :ok
    report = "** Base.Debug #{inspect(self())} event log:\n" <>
    "** Base.Debug #{inspect(self())} " <>
    "message out (to #{inspect(pid)}): :hello\n" <>
    "\n"
    assert TestIO.binread() === report
  end

  test "stats with 0 events and get stats" do
    min_start = seconds()
    start_reductions = reductions()
    debug = Base.Debug.new([{ :stats, true }])
    assert stats = Base.Debug.get_stats(debug)
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
    debug = Base.Debug.new([{ :stats, true }])
    debug = Base.Debug.event(debug, { :in, :hello })
    assert stats = Base.Debug.get_stats(debug)
    assert stats[:in] === 1
  end

  test "stats with call message in and get stats" do
    debug = Base.Debug.new([{ :stats, true }])
    debug = Base.Debug.event(debug, { :in, :hello, self() })
    assert stats = Base.Debug.get_stats(debug)
    assert stats[:in] === 1
  end

  test "stats with message out and get stats" do
    debug = Base.Debug.new([{ :stats, true }])
    debug = Base.Debug.event(debug, { :out, :hello, self() })
    assert stats = Base.Debug.get_stats(debug)
    assert stats[:out] === 1
  end

  test "stats with one of each event and print stats" do
    debug = Base.Debug.new([{ :stats, true }])
    debug = Base.Debug.event(debug, { :in, :hello, })
    debug = Base.Debug.event(debug, { :in, :hello, self() })
    debug = Base.Debug.event(debug, { :out, :hello, self() })
    assert Base.Debug.print_stats(debug) === :ok
    output = TestIO.binread()
    pattern = "\\A\\*\\* Base.Debug #{inspect(self())} statistics:\n" <>
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
    debug = Base.Debug.new([])
    assert Base.Debug.print_stats(debug) === :ok
    report = "** Base.Debug #{inspect(self())} statistics not active\n" <>
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
