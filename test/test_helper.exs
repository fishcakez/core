ExUnit.start

defmodule TestIO do

  use GenEvent.Behaviour

  def setup_all() do
    :ok = :error_logger.add_report_handler(TestIO)
    :error_logger.tty(false)
  end

  def setup() do
    stdio = Process.group_leader()
    { :ok, stringio } = StringIO.start_link(<<>>)
    Process.group_leader(self(), stringio)
    { :ok, [{ :stdio, stdio }, { StringIO, stringio }] }
  end

  def teardown(context) do
    stringio = Keyword.get(context, StringIO)
    stdio = Keyword.get(context, :stdio)
    Process.group_leader(self(), stdio)
    StringIO.close(stringio)
  end

  def teardown_all() do
    :error_logger.tty(true)
    :error_logger.delete_report_handler(TestIO)
  end

  def binread() do
    # sync with :error_logger so that everything sent by current process has
    # been written. Also checks handler is alive and writing to StringIO.
    :pong = :gen_event.call(:error_logger, TestIO, :ping, 5000)
    { input, output } = StringIO.peek(Process.group_leader())
    << input :: binary, output :: binary >>
  end

  def init(_args) do
    { :ok, nil }
  end

  def handle_event({ :error, device, { _pid, format, data } }, state) do
    :io.format(device, format ++ '~n', data)
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
