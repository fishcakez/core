ExUnit.start

defmodule TestIO do

  use ExUnit.Callbacks
  use GenEvent

  def setup_all() do
    :ok = :error_logger.add_report_handler(TestIO)
    :error_logger.tty(false)
    on_exit(fn() ->
        :error_logger.tty(true)
        :error_logger.delete_report_handler(TestIO)
      end)
    :ok
  end

  def setup() do
    stdio = Process.group_leader()
    { :ok, stringio } = StringIO.open(<<>>)
    Process.group_leader(self(), stringio)
    on_exit(fn() ->
        Process.group_leader(self(), stdio)
      end)
    :ok
  end

  def binread() do
    # sync with :error_logger so that everything sent by current process has
    # been written. Also checks handler is alive and writing to StringIO.
    :pong = :gen_event.call(:error_logger, TestIO, :ping, 5000)
    { input, output } = StringIO.contents(Process.group_leader())
    << input :: binary, output :: binary >>
  end

  def init(_args) do
    { :ok, nil }
  end

  def handle_event({ :error, device, { _pid, format, data } }, state) do
    try do
      :io.format(device, format ++ '~n', data)
    catch
      # device can receive exit signal from parent causing it to exit
      # before replying.
      :error, :terminated ->
        :ok
    end
    { :ok, state }
  end

  def handle_event(_other, state) do
    { :ok, state }
  end

  def handle_call(:ping, state) do
    { :ok, :pong, state }
  end

  def terminate({ :error, reason }, _state) do
    IO.puts(:user, "error in TestIO: #{inspect(reason)}")
  end

  def terminate(_reason, _state) do
    :ok
  end

end

defmodule GS do

  use GenServer

  def start_link(fun, debug_opts \\ []) do
    :gen_server.start_link(__MODULE__, fun, [{ :debug, debug_opts }])
  end

  def init(fun), do: fun.()

  def code_change(_oldvsn, _oldfun, newfun), do: newfun.()

end

defmodule GE do

  use GenEvent

  def start_link(fun) do
    { :ok, pid } = :gen_event.start_link()
    :ok = :gen_event.add_handler(pid, __MODULE__, fun)
    { :ok, pid }
  end

  def init(fun), do: fun.()

  def code_change(_oldvsn, _oldfun, newfun), do: newfun.()

end

defmodule GFSM do

  @behaviour :gen_fsm

  def start_link(fun, debug_opts \\ []) do
    :gen_fsm.start_link(__MODULE__, fun, [{ :debug, debug_opts }])
  end

  def init(fun), do: fun.()

  def state(_event, fun) do
    { :next_state, :state, fun }
  end

  def state(_event, _from, fun) do
    { :next_state, :state, fun }
  end

  def handle_event(_evemt, :state, fun) do
    { :next_state, :state, fun }
  end

  def handle_sync_event(_event, _from, :state, fun) do
    { :next_state, :state, fun }
  end

  def handle_info(_info, :state, fun) do
    { :next_state, :state, fun }
  end

  def code_change(_oldvsn, :state, _oldfun, extra) do
    extra.()
  end

  def terminate(_reason, :state, _fun) do
    :ok
  end

end
