defmodule Base.Debug do
  @moduledoc """
  Functions for handling debug events and statistics.

  Start the VM with `--gen-debug` to turn on logging and statistics by default.

  The functions in this module are intended for use during testing and
  development.

  ## Examples

      defmodule Base.PingPong do

        use Base.Behaviour

        @spec ping(Base.t) :: :pong
        def ping(process), do: Base.call(process, __MODULE__, :ping, 5000)

        @spec count(Base.t) :: non_neg_integer
        def count(process), do: Base.call(process, __MODULE__, :count, 5000)

        @spec close(Base.t) :: :ok
        def close(process), do: Base.call(process, __MODULE__, :close, 5000)

        @spec start_link() :: { :ok, pid }
        def start_link() do
          Base.start_link(nil, __MODULE__, nil, [{ :debug, [:log, :stats] }])
        end

        def init(_parent, debug, nil) do
          Base.init_ack()
          loop(0, debug)
        end

        defp loop(count, debug) do
          receive do
            { __MODULE__, from, :ping } ->
              debug = Base.Debug.event(debug, { :in, :ping, elem(from, 0) })
              Base.reply(from, :pong)
              debug = Base.Debug.event(debug, { :out, :pong, elem(from, 0) })
              count = count + 1
              debug = Base.Debug.event(debug, { :count, count })
              loop(count, debug)
            { __MODULE__, from, :count } ->
              debug = Base.Debug.event(debug, { :in, :count, elem(from, 0) })
              Base.reply(from, count)
              debug = Base.Debug.event(debug, { :out, count, elem(from, 0) })
              loop(count, debug)
            { __MODULE__, from, :close } ->
              debug = Base.Debug.event(debug, { :in, :close, elem(from, 0) })
              Base.reply(from, :ok)
              debug = Base.Debug.event(debug, { :out, :ok, elem(from, 0)  })
              terminate(count, debug)
          end
        end

        defp terminate(count, debug) do
          debug = Base.Debug.event(debug, { :EXIT, :normal })
          Base.Debug.print_stats(debug)
          Base.Debug.print_log(debug)
          exit(:normal)
        end

      end

  """

  @type event :: any
  @type hook_state :: any
  @type hook ::
    ((proc_state :: any, event, hook_state) -> :done | hook_state )
  @type option :: :trace | :log | { :log, pos_integer } | :statistics | :stats |
    { :log_to_file, Path.t } | { :install, { hook, hook_state } }
  @type t :: [:sys.dbg_opt]
  @type stats :: map

  ## macros

  @doc """
  Macro for handling debug events.

  The macro will become a no-op if Mix.env == :prod and no debug features will
  be carried out, even if the debug object has debugging enabled.

  When the debug object has no debugging features enabled the created code will
  not make any external calls and is nearly a no-op.

  Should only be used by the process that created the debug object.
  """
  defmacro event([], _event), do: []
  defmacro event(debug, event) do
    if handle_event?() do
      quote do
        case unquote(debug) do
          [] ->
            unquote(debug)
          _ ->
            :sys.handle_debug(unquote(debug), &Base.Debug.print_event/3,
              Base.get_name(), unquote(event))
        end
      end
    else
      debug
    end
  end

  ## api

  @doc """
  Creates a new debug object.

  `new/0` will use default debug options, with the `--gen-debug` VM option this
  will be `[:statistics, :log]` - unless overridden by `set_opts/1`.
  """
  @spec new([option]) :: t
  def new(opts \\ get_opts()) do
    Enum.map(opts, &map_option/1)
      |> :sys.debug_options()
  end

  @doc """
  Returns the default options.
  """
  @spec get_opts() :: [option]
  def get_opts(), do: :ets.lookup_element(__MODULE__, :options, 2)

  @doc """
  Sets the default options.
  """
  @spec set_opts([option]) :: :ok
  def set_opts(opts) do
    true = :ets.update_element(__MODULE__, :options, { 2, opts })
    :ok
  end

  @doc false
  @spec ensure_table() :: :ok
  def ensure_table() do
    if :ets.info(__MODULE__) === :undefined do
      :ets.new(__MODULE__,
        [:set, :public, :named_table, { :read_concurrency, true }])
      set_default_options()
    end
    :ok
  end

  ## event

  @doc false
  @spec print_event(IO.device, event, Base.name) :: :ok
  def print_event(device, event, name) do
    header = "** Base.Debug #{Base.format(name)} "
    formatted_event = format_event(event)
    IO.puts(device, [header | formatted_event])
  end

  ## logs

  @doc """
  Returns a list of stored events in order.
  Returns nil if logging is disabled.

  Should only be used by the process that created the debug object.
  """
  @spec get_log(t) :: [event] | nil
  def get_log(debug) do
    case :sys.get_debug(:log, debug, nil) do
      nil ->
        nil
      { _size, raw_log } ->
        Enum.reduce(raw_log, [], &get_log/2)
    end
  end

  @doc """
  Prints logged events to the device (defaults to :stdio) if logging is enabled.

  Should only be used by the process that created the debug object.
  """
  @spec print_log(t, IO.device) :: :ok
  def print_log(debug, device \\ :stdio) do
    case :sys.get_debug(:log, debug, nil) do
      nil ->
        :ok
      { _size, raw_log } ->
        write_raw_log(device, Enum.reverse(raw_log))
    end
  end

  ## stats

  @doc """
  Returns a map of statistics.
  Returns nil if statstics is disabled.

  Should only be used by the process that created the debug object.
  """
  @spec get_stats(t) :: stats | nil
  def get_stats(debug) do
   case :sys.get_debug(:statistics, debug, nil) do
     { start_time, { :reductions, start_reductions }, msg_in, msg_out } ->
       current_time = :erlang.localtime()
       { :reductions, current_reductions } = Process.info(self(), :reductions)
       reductions = current_reductions - start_reductions
       %{ start_time: start_time, current_time: current_time,
          reductions: reductions, in: msg_in, out: msg_out }
     nil ->
       nil
   end
  end

  @doc """
  Prints statistics to the device (defaults to :stdio) if statistics are
  enabled.

  Should only be used by the process that created the debug object.
  """
  @spec print_stats(t, IO.device) :: :ok
  def print_stats(debug, device \\ :stdio) do
    case get_stats(debug) do
      nil ->
        :ok
      stats ->
        write_stats(device, stats)
    end
  end

  ## internal

  ## options

  defp map_option(:stats), do: :statistics
  defp map_option(option), do: option

  defp set_default_options() do
    options = :application.get_env(:base, :options, [])
    case :init.get_argument(:generic_debug) do
      { :ok, _ } ->
        :ets.insert(__MODULE__, { :options, generic_debug(options) })
      :error ->
        :ets.insert(__MODULE__, { :options, options })
    end
  end

  defp generic_debug(options) do
    add_log(options)
      |> add_statistics()
  end

  defp add_log(options) do
    if Enum.any?(options, &log_option?/1) do
      options
    else
      [:log | options]
    end
  end

  defp log_option?(:log), do: true
  defp log_option?({ :log, _ }), do: true
  defp log_option?(_other), do: false

  defp add_statistics(options) do
    if Enum.member?(options, :statistics) or Enum.member?(options, :stats) do
      options
    else
      [:stats | options]
    end
  end

  ## event

  defp handle_event?() do
    cond do
      # Mix is not loaded, turn debugging on
      not :erlang.function_exported(Mix, :env, 0) ->
        true
      # prod(uction) mode, turn debugging off
      Mix.env === :prod ->
        false
      # Mix is loaded but not prod, turn debugging on
      true ->
        true
    end
  end

  defp format_event({ :in, msg, from }) do
    ["message in (from ", inspect(from), "): ", inspect(msg)]
  end

  defp format_event({ :in, msg }) do
    ["message in: " | inspect(msg)]
  end

  defp format_event({ :out, msg, to }) do
    ["message out (to ", inspect(to), "): ", inspect(msg)]
  end

  defp format_event(event), do: inspect(event)

  ## log

  defp get_log({ event, _state, _report }, acc), do: [event|acc]

  defp write_raw_log(device, []) do
     header = "** Base.Debug #{Base.format()} event log is empty\n"
    IO.puts(device, header)
  end

  defp write_raw_log(device, raw_log) do
    formatted_log = format_raw_log(raw_log)
    header = "** Base.Debug #{Base.format()} event log:\n"
    IO.puts(device, [header | formatted_log])
  end

  # Collect log into a single binary so that it is written to the device in
  # one, rather than many seperate writes. With seperate writes the events
  # could be interwoven with other writes to the device.
  defp format_raw_log(raw_log) do
    { :ok, device } = StringIO.start_link(<<>>)
    try do
      format_raw_log(raw_log, device)
    else
      formatted_log ->
        formatted_log
    after
      StringIO.stop(device)
    end
  end

  defp format_raw_log(raw_log, device) do
    _ = lc { event, state, print } inlist raw_log do
      print.(device, event, state)
    end
    { input, output } = StringIO.peek(device)
    [input | output]
  end

  ## stats

  defp write_stats(device, stats) do
    header = "** Base.Debug #{Base.format()} statistics:\n"
    formatted_stats = format_stats(stats)
    IO.puts(device, [header | formatted_stats])
  end

  defp format_stats(%{ start_time: start_time, current_time: current_time,
    reductions: reductions, in: msg_in, out: msg_out }) do
    ["   Start Time: #{format_time(start_time)}\n",
      "   Current Time: #{format_time(current_time)}\n",
      "   Messages In: #{msg_in}\n",
      "   Messages Out: #{msg_out}\n",
      "   Reductions: #{reductions}\n"]
  end

  defp format_time({ { year, month, day }, { hour, min, sec } }) do
    format = '~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B'
    args = [year, month, day, hour, min, sec]
    :io_lib.format(format, args)
      |> iolist_to_binary()
  end

end
