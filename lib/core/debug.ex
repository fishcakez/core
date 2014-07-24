defmodule Core.Debug do
  @moduledoc """
  Functions for handling debug events and statistics.

  Start the VM with `--gen-debug` to turn on logging and statistics by default.

  The functions in this module are intended for use during testing and
  development.

  ## Examples

      defmodule Core.PingPong do

        use Core

        @spec ping(Core.t) :: :pong
        def ping(process), do: Core.call(process, __MODULE__, :ping, 5000)

        @spec count(Core.t) :: non_neg_integer
        def count(process), do: Core.call(process, __MODULE__, :count, 5000)

        @spec close(Core.t) :: :ok
        def close(process), do: Core.call(process, __MODULE__, :close, 5000)

        @spec start_link() :: { :ok, pid }
        def start_link() do
          Core.start_link(nil, __MODULE__, nil,
            [{ :debug, [{ :log, 10 }, { :stats, true }] }])
        end

        def init(_parent, debug, nil) do
          Core.init_ack()
          loop(0, debug)
        end

        defp loop(count, debug) do
          receive do
            { __MODULE__, from, :ping } ->
              debug = Core.Debug.event(debug, { :in, :ping, elem(from, 0) })
              Core.reply(from, :pong)
              debug = Core.Debug.event(debug, { :out, :pong, elem(from, 0) })
              count = count + 1
              debug = Core.Debug.event(debug, { :count, count })
              loop(count, debug)
            { __MODULE__, from, :count } ->
              debug = Core.Debug.event(debug, { :in, :count, elem(from, 0) })
              Core.reply(from, count)
              debug = Core.Debug.event(debug, { :out, count, elem(from, 0) })
              loop(count, debug)
            { __MODULE__, from, :close } ->
              debug = Core.Debug.event(debug, { :in, :close, elem(from, 0) })
              Core.reply(from, :ok)
              debug = Core.Debug.event(debug, { :out, :ok, elem(from, 0)  })
              terminate(count, debug)
          end
        end

        defp terminate(count, debug) do
          debug = Core.Debug.event(debug, { :EXIT, :normal })
          Core.Debug.print_stats(debug)
          Core.Debug.print_log(debug)
          exit(:normal)
        end

      end

  """

  @type event :: any
  @type hook_state :: any
  @type hook ::
    ((hook_state, event, process_term :: any) -> :done | hook_state )
  @type option :: { :trace, boolean } | { :log, non_neg_integer } |
    { :stats, boolean } | { :log_file, Path.t | nil } |
    { :hook, { hook, hook_state | nil } }
  @type t :: [:sys.dbg_opt]
  @type stats :: map
  @typep report :: ((IO.device, report, any) -> any)

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
            :sys.handle_debug(unquote(debug), &Core.Debug.print_event/3,
              Core.get_name(), unquote(event))
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
    parse_options(opts)
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
  @spec print_event(IO.device, event, Core.name) :: :ok
  def print_event(device, event, name) do
    header = "** Core.Debug #{Core.format(name)} "
    formatted_event = format_event(event)
    IO.puts(device, [header | formatted_event])
  end

  ## logs

  @doc """
  Returns a list of stored events in order.

  Should only be used by the process that created the debug object.
  """
  @spec get_log(t) :: [event]
  def get_log(debug) do
    get_raw_log(debug)
      |> log_from_raw()
  end

  @doc """
  Prints logged events to the device (defaults to :stdio).

  Should only be used by the process that created the debug object.
  """
  @spec print_log(t, IO.device) :: :ok
  def print_log(debug, device \\ :stdio) do
    case get_raw_log(debug) do
      [] ->
        write_raw_log(device, [])
      raw_log ->
        write_raw_log(device, raw_log)
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
    case get_raw_stats(debug) do
      :no_statistics ->
        nil
      raw_stats ->
        stats_from_raw(raw_stats)
    end
  end

  @doc """
  Prints statistics to the device (defaults to :stdio).

  Should only be used by the process that created the debug object.
  """
  @spec print_stats(t, IO.device) :: :ok
  def print_stats(debug, device \\ :stdio) do
    stats = get_stats(debug)
    write_stats(device, stats)
  end

  @doc """
  Prints statistics and logs (if active) to the device (defaults to :stdio).

  Should only be used by the process that created the debug object
  """
  @spec print(t, IO.device) :: :ok
  def print(debug, device \\ :stdio) do
    maybe_print_stats(debug, device)
    maybe_print_log(debug, device)
  end

  @doc false
  @spec get_raw_log(t) :: [{ event, any, report}]
  # return value used in get_status calls
  def get_raw_log(debug) do
    case :sys.get_debug(:log, debug, []) do
      [] ->
        []
      { _max, rev_raw_log } ->
        Enum.reverse(rev_raw_log)
    end
  end

  @doc false
  @spec log_from_raw([{ event, any, report }]) :: [event]
  def log_from_raw(raw_log) do
    Enum.map(raw_log, fn({ event, _state, _report }) -> event end)
  end

  @doc false
  @spec write_raw_log(IO.device, Core.t, [{ event, any, report }]) :: :ok
  def write_raw_log(device, process \\ Core.get_name(), raw_log)


  def write_raw_log(device, process, []) do
     header = "** Core.Debug #{Core.format(process)} event log is empty\n"
    IO.puts(device, header)
  end

  def write_raw_log(device, process, raw_log) do
    formatted_log = format_raw_log(raw_log)
    header = "** Core.Debug #{Core.format(process)} event log:\n"
    IO.puts(device, [header | formatted_log])
  end

  @doc false
  def get_raw_stats(debug) do
    case :sys.get_debug(:statistics, debug, :no_statistics) do
      :no_statistics ->
        :no_statistics
      { start_time, { :reductions, start_reductions }, msg_in, msg_out } ->
        current_time = :erlang.localtime()
        { :reductions, current_reductions } = Process.info(self(), :reductions)
        reductions = current_reductions - start_reductions
        [start_time: start_time, current_time: current_time,
          reductions: reductions, messages_in: msg_in, messages_out: msg_out]
    end
  end

  @doc false
  @spec stats_from_raw(:no_statistics | [{ atom, any}]) :: stats | nil
  def stats_from_raw(:no_statistics), do: nil

  def stats_from_raw(raw_stats) do
    stats = Enum.into(raw_stats, Map.new())
    # rename messages_in/out for convenience
    { msg_in, stats } = Map.pop(stats, :messages_in)
    { msg_out, stats } = Map.pop(stats, :messages_out)
    Map.put(stats, :in, msg_in)
      |> Map.put(:out, msg_out)
  end

  @doc false
  def write_stats(device, process \\ Core.get_name(), stats)

  def write_stats(device, process, nil) do
    header = "** Core.Debug #{Core.format(process)} statistics not active\n"
    IO.puts(device, header)
  end

  def write_stats(device, process, stats) do
    header = "** Core.Debug #{Core.format(process)} statistics:\n"
    formatted_stats = format_stats(stats)
    IO.puts(device, [header | formatted_stats])
  end

  ## internal

  ## options

  defp parse_options([]), do: []

  defp parse_options(opts) do
    parse_trace([], opts)
      |> parse_log(opts)
      |> parse_stats(opts)
      |> parse_log_file(opts)
      |> parse_hooks(opts)
  end

  defp parse_trace(acc, opts) do
    case Keyword.get(opts, :trace, false) do
      true ->
        [:trace | acc]
      false ->
        acc
    end
  end

  defp parse_log(acc, opts) do
    case Keyword.get(opts, :log, 0) do
      0 ->
        acc
      max when is_integer(max) and max > 0 ->
        [{ :log, max } | acc]
    end
  end

  defp parse_stats(acc, opts) do
    case Keyword.get(opts, :stats, false) do
      true ->
        [:statistics | acc]
      false ->
        acc
    end
  end

  defp parse_log_file(acc, opts) do
    case Keyword.get(opts, :log_file, nil) do
      nil ->
        acc
      path ->
        [ { :log_to_file, path } | acc ]
    end
  end

  defp parse_hooks(acc, opts) do
    Keyword.get_values(opts, :hook)
      |> Enum.reduce([], &add_hook/2)
      |> Enum.reduce(acc, &hook_options/2)
  end

  defp add_hook({hook, hook_state}, acc) when is_function(hook, 3) do
    case List.keymember?(acc, hook, 0) do
      true ->
        acc
      false ->
        [{ hook, hook_state } | acc]
    end
  end

  defp hook_options({ _hook, nil }, acc), do: acc
  defp hook_options(other, acc), do: [{ :install, other} | acc]

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

  # Collect log into a single binary so that it is written to the device in
  # one, rather than many seperate writes. With seperate writes the events
  # could be interwoven with other writes to the device.
  defp format_raw_log(raw_log) do
    { :ok, device } = StringIO.open(<<>>)
    try do
      format_raw_log(raw_log, device)
    else
      formatted_log ->
        formatted_log
    after
      StringIO.close(device)
    end
  end

  defp format_raw_log(raw_log, device) do
    Enum.each(raw_log, &print_raw_event(device, &1))
    { input, output } = StringIO.contents(device)
    [input | output]
  end

  defp print_raw_event(device, { event, state, print }) do
    print.(device, event, state)
  end

  ## stats

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
      |> IO.iodata_to_binary()
  end

  ## print

  defp maybe_print_stats(debug, device) do
    case get_stats(debug) do
      nil ->
        :ok
      stats ->
        write_stats(device, stats)
    end
  end

  defp maybe_print_log(debug, device) do
    case :sys.get_debug(:log, debug, nil) do
      nil ->
        :ok
      { _max, raw_log } ->
        write_raw_log(device, Enum.reverse(raw_log))
    end
  end

end
