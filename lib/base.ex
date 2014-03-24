defmodule Base do
  @moduledoc """
  Functions for handling process initiation, communication and termination.

  This module provides the basic features required for building OTP compliant
  processes. There are a few examples for using these functions to create OTP
  processes in the documentation for `Base.Behaviour` and `Base.Debug`.

  Many functions in this module are only intended for use in processes initiated
  by functions in this module.
  """

  use Behaviour

  defcallback  init(parent, Base.Debug.t, args) :: no_return

  ## start/spawn types

  @type local_name :: atom()
  @type global_name :: { :global, any }
  @type via_name :: { :via, module, any }
  @type name :: nil | local_name | global_name | via_name
  @typep args :: any
  @type option :: { :timeout, timeout } | { :debug, [Base.Debug.option] } |
    { :spawn, [Process.spawn_opt] }
  @type start_return :: { :ok, pid } | { :ok, pid, any } | :ignore |
    { :error, any }

  ## communication types

  @type process :: pid | { local_name, node }
  @type t :: name | process
  @type label :: any
  @typep request :: any
  @opaque tag :: reference
  @type from :: { pid, tag }
  @typep response :: any

  ## general types

  @typep extra :: any
  @typep reason :: Exception.t | { Exception.t, Exception.stacktrace } | atom |
    { atom, any }
  @typep state :: any
  @type parent :: pid

  ## exceptions

  defexception UncaughtThrowError, [actual: nil] do
    def message(exception) do
      "uncaught throw: #{inspect(exception.actual)}"
    end
  end

  defexception CallError, [:target, :process, :label, :request, :reason] do
    def message(exception) do
      "#{format_label(exception.label)} #{inspect(exception.request)} to " <>
      "#{Base.format(exception.target)} " <>
      "failed: #{format_reason(exception.reason, exception.process)}"
    end

    defp format_label(label) when is_atom(label) do
      case to_string(label) do
        # label is a module
        "Elixir." <> _rest ->
          inspect(label)
        other ->
          other
      end
    end

    defp format_label(label), do: inspect(label)

    defp format_reason(:noproc, pid) when is_pid(pid) do
      "#{inspect(pid)} is not alive"
    end

    # _other can be { name, node_name } or nil
    defp format_reason(:noproc, _other) do
      "no process associated with that name"
    end

    defp format_reason(:noconnection, pid) when is_pid(pid) do
      "#{inspect(pid)} on #{node(pid)} is disconnected"
    end

    defp format_reason(:noconnection, { name, node_name }) do
      "#{name} on #{node_name} is disconnected"
    end

    defp format_reason(:nomonitor, process) do
      "#{format_process(process)} can not be monitored"
    end

    defp format_reason(:timeout, process) do
      "#{format_process(process)} did not respond in time"
    end

    defp format_reason({ :EXIT, :normal }, process) do
      "#{format_process(process)} exited normally"
    end

    defp format_reason({ :EXIT, :shutdown }, process) do
      "#{format_process(process)} shutdown"
    end

    defp format_reason({ :EXIT, { :shutdown, reason } }, process) do
      "#{format_process(process)} shutdown with reason: #{inspect(reason)}"
    end

    defp format_reason({ :EXIT, :killed }, process) do
      "#{format_process(process)} was killed"
    end

    defp format_reason({ :EXIT, { exception, stack } = reason }, process)
        when is_exception(exception) and stack !== nil do
      try do
        Exception.format_stacktrace(stack)
      rescue
        # not a stacktrace
        _exception ->
          "#{format_process(process)} exited with reason: #{inspect(reason)}"
      else
        formatted_stack ->
          "#{format_process(process)} raised an exception\n" <>
          "   (#{inspect(elem(exception, 0))}) #{exception.message}\n" <>
          "#{formatted_stack}"
      end
    end

    defp format_reason({ :EXIT, reason }, process) do
      "#{format_process(process)} exited with reason: #{inspect(reason)}"
    end

    defp format_process(pid) when is_pid(pid) do
      inspect(pid)
    end

    defp format_process({ name, node_name }) do
      "#{name} on #{node_name}"
    end
  end

  ## start/spawn api

  @doc """
  Start a parentless Base process without a link.

  This function will block until the created processes sends an acknowledgement,
  exits or the timeout is reached. If the timeout is reached the created process
  is killed and `{ :error, :timeout }` will be returned.

  A process created with this function will automatically send error reports to
  the error logger if an exception is raised (and not rescued). A crash report
  is also sent when the process exits with an abnormal reason.

  To atomically spawn and link to the process include the `:spawn` option
  `:link`.
  """
  @spec start(name, module, args, [option]) :: start_return
  def start(name \\ nil, mod, args, opts \\ []) do
    spawn_opts = Keyword.get(opts, :spawn, [])
    timeout = Keyword.get(opts, :timeout, :infinity)
    init_args = [mod, name, nil, args, self(), opts]
    :proc_lib.start(__MODULE__, :init, init_args, timeout, spawn_opts)
  end

  @doc """
  Start a Base process with a link.

  This function will block until the created processes sends an acknowledgement,
  exits or the timeout is reached. If the timeout is reached the created process
  is killed and `{ :error, :timeout }` will be returned.

  A process created with this function will automatically send error reports to
  the error logger if an exception is raised (and not rescued). A crash report
  is also sent when the process exits with an abnormal reason.

  A processes created with this function should exit when its parent does and
  with the same reason.
  """
  @spec start_link(name, module, args, [option]) :: start_return
  def start_link(name \\ nil, mod, args, opts \\ []) do
    spawn_opts = Keyword.get(opts, :spawn, [])
    init_args = [mod, name, self(), args, self(), opts]
    timeout = Keyword.get(opts, :timeout, :infinity)
    :proc_lib.start_link(__MODULE__, :init,  init_args, timeout, spawn_opts)
  end

  @doc """
  Spawn a parentless Base process without a link.

  A process created with this function will automatically send error reports to
  the error logger if an exception is raised (and not rescued). A crash report
  is also sent when the process exits with an abnormal reason.

  To atomically spawn and link to the process include the `:spawn` option
  `:link`.
  """
  @spec spawn(name, module, args, [option]) :: pid
  def spawn(name \\ nil, mod, args, opts \\ []) do
    spawn_opts = Keyword.get(opts, :spawn, [])
    init_args =  [mod, name, nil, args,  nil, opts]
    :proc_lib.spawn_opt(__MODULE__, :init, init_args, spawn_opts)
  end

  @doc """
  Spawn a Base process with a link.

  A process created with this function will automatically send error reports to
  the error logger if an exception is raised (and not rescued). A crash report
  is also sent when the process exits with an abnormal reason.

  A processes created with this function should exit when its parent does and
  with the same reason.
  """
  @spec spawn_link(name | nil, module, any, [option]) :: pid
  def spawn_link(name \\ nil, mod, args, opts \\ []) do
    spawn_opts = Keyword.get(opts, :spawn, [])
    init_args =  [mod, name, self(), args, nil, opts]
    :proc_lib.spawn_opt(__MODULE__, :init, init_args, [:link | spawn_opts])
  end


  @doc """
  Sends an acknowledgment to the starter process.

  The starter process will block until it receives the acknowledgement. The
  start function will return `{ :ok, pid }`.

  If the process was created using a spawn function no acknowledgment is sent.

  This function is only intended for use by processes created by this module.
  """
  @spec init_ack() :: :ok
  def init_ack() do
    case get_starter() do
      starter when starter === self() -> :ok
      starter -> :proc_lib.init_ack(starter, { :ok, self() })
    end
  end

  @doc """
  Sends an acknowledgment to the starter process with extra information.

  The starter process will block until it receives the acknowledgement. The
  start function will return `{ :ok, pid, extra }`.

  If the process was created using a spawn function no acknowledgment is sent.

  This function is only intended for use by processes created by this module.
  """
  @spec init_ack(extra) :: :ok
  def init_ack(extra) do
    case get_starter() do
      starter when starter === self() -> :ok
      starter -> :proc_lib.init_ack(starter, { :ok, self(), extra })
    end
  end

  @doc """
  Sends an acknowledgment to the starter process to ignore the current process.

  This function is an alternative to `init_ack/0` and should be used be signal
  that nothing will occur in the created process.

  Before sending the acknowledgment the process will unregister any name that
  was associated with the process during initiation.

  After sending the acknowledgment the process will exit with reason `:normal`
  so this function should only be used as a tail call.

  The starter process will block until it receives the acknowledgement. The
  start function will return `:ignore`.

  If the process was created using a spawn function no acknowledgment is sent.

  This function is only intended for use by processes created by this module.
  """
  @spec init_ignore :: no_return
  def init_ignore() do
    unregister()
    starter = get_starter()
    if starter !== self(), do: :proc_lib.init_ack(starter, :ignore)
    exit(:normal)
  end

  @doc """
  Sends an acknowledgment to the starter process that the current process failed
  to initiate.

  This function is an alternative to `init_ack/0` and should be used be signal
  the rason why initiation failed.

  Before sending the acknowledgment the process may print debug information and
  log an error with the error logger. If the reason is of the form:
  `{ exception, stacktrace }`, the error will note that an exception was raised
  format the exception and stacktrace. Also any name that was associated with
  the process during initiation will be unregistered.

  After sending the acknowledgment the process will exit with the reason passed.
  As this function exits it should only be used as a tail call.

  The starter process will block until it receives the acknowledgement. The
  start function will return `{ :error, reason }`, where reason is the same
  reason as exiting.

  If the process was created using a spawn function no acknowledgment is sent.

  This function is only intended for use by processes created by this module.
  """
  @spec init_stop(module, parent, Base.Debug.t, args, reason,
    Base.Debug.event) :: no_return
  def init_stop(mod, parent, debug, args, reason, event \\ nil)

  def init_stop(mod, parent, debug, args, reason, event) do
    type = exit_type(reason)
    starter = get_starter()
    if starter === self() and type === :abnormal do
      report_init_stop(mod, parent, args, reason, event)
    end
    if type === :abnormal, do: print_debug(debug)
    unregister()
    if starter !== self(), do: :proc_lib.init_ack(starter, { :error, reason })
    exit(reason)
  end

  @doc """
  Stops a Base process.

  Before exiting the process may print debug information and will send an error
  report to the error logger when the reason is not `:normal`, `:shutdown` or of
  the form `{ :shutdown, any }`. If the reason is of the form:
  `{ exception, stacktrace }`, the error will note that an exception was raised
  format the exception and stacktrace. A crash report with additional
  information will also be sent to the error logger.

  The process will exit with the reason passed. As this function exits it should
  only be used as a tail call.

  This function is only intended for use by processes created by this module.
  """
  @spec stop(module, state, parent, Base.Debug.t, reason,
    Base.Debug.event) :: no_return
  def stop(mod, state, parent, debug, reason, event \\ nil)

  def stop(mod, state, parent, debug, reason, event) do
    type = exit_type(reason)
    if type === :abnormal do
      report_stop(mod, state, parent, reason, event)
      print_debug(debug)
    end
    exit(reason)
  end

  ## communication api

  @doc """
  Returns the pid or `{ local_name, node }` of the Base process associated with
  the name or process.
  Returns `nil` if no process is associated with the name.

  The returned process may not be alive.
  """
  @spec whereis(t) :: process | nil
  def whereis(pid) when is_pid(pid), do: pid
  def whereis(name) when is_atom(name), do: Process.whereis(name)

  def whereis({ :global, name }) do
    case :global.whereis_name(name) do
      :undefined ->
        nil
      pid ->
        pid
    end
  end

  def whereis({ name, node_name })
      when is_atom(name) and node_name === node() do
    Process.whereis(name)
  end

  def whereis({ name, node_name } = process)
      when is_atom(name) and is_atom(node_name) do
    process
  end

  def whereis({ :via, mod, name }) when is_atom(mod) do
    case mod.whereis_name(name) do
      :undefined ->
        nil
      pid ->
        pid
    end
  end

  @doc """
  Calls the Base process associated the with name or process and returns the
  reponse.
  Raises a `Base.CallError` if the process does not reply before the timeout or
  if the process exits without replying.

  The message is sent in the form `{ label, from, request }`. A response is sent
  by calling `reply(from, response)`.

  Rescuing a `Base.CallError` may result in unexpected messages arriving in the
  calling processes mailbox. Therefore it is recommended to terminate soon after
  if a `Base.CallError` must be rescued.
  """
  @spec call(t, label, request, timeout) :: response
  def call(target, label, request, timeout) do
    case whereis(target) do
      pid when is_pid(pid) ->
        call(pid, target, label, request, timeout)
      { local_name, node_name } = process
          when is_atom(local_name) and is_atom(node_name) ->
        call(process, target, label, request, timeout)
      nil ->
        raise Base.CallError, [target: target, label: label, request: request,
          reason: :noproc]
    end
  end

  @doc """
  Sends a response to a call message.

  The first argument is the `from` term from a call message of the form:
  `{ label, from, request }`.
  """
  @spec reply(from, response) :: response
  def reply({ to, tag }, response) do
    try do
      Process.send(to, { tag, response })
    catch
      ArgumentError ->
        response
    end
  end

  @doc """
  Sends a message to the Base process associated with the name or process.

  This function will not raise an exception if there is not a process associated
  with the name.

  This function will not block to attempt an connection to a disconnected node.
  Instead it will spawn a process to make the attempt and return `:ok`
  immediately. Therefore messages to processes on other nodes may not arrive
  out of order, if they are received. Messages to processes on the same node
  will arrive in order, if they are received.
  """
  @spec cast(t, label, request) :: :ok
  def cast(target, label, request) do
    case whereis(target) do
      nil ->
        :ok
      process ->
        msg = { label, request }
        cast(process, msg)
    end
  end

  @doc """
  Sends a message to the Base process associated with the name or process.

  This function will raise an ArgumentError if a name is provided and no process
  is associated with the name - unless the name is for a locally registered name
  on another node. Similar to the behaviour of `Process.send/2`.

  This function will block to attempt a connection to a disconnected node, and
  so messages sent by this function will arrive in order, if they are received.
  """
  @spec send(t, request) :: request
  def send(target, msg) do
    case whereis(target) do
      nil ->
        raise ArgumentError,
          message: "no process associated with #{format(target)}"
      process ->
        Process.send(process, msg)
    end
  end

  ## hibernation api

  @doc """
  Hibernates the Base process. Must be used to hibernate Base processes to
  ensure exceptions (and exits) are handled correctly.

  This function throws away the stack and should only be used as a tail call.

  When the process leaves hibernation the following will be called:
  `apply(mod, fun, [state, parent, debug] ++ args)`

  This function is only intended for use by processes created by this module.
  """
  @spec hibernate(module, atom, state, parent, Base.Debug.t, [any]) :: no_return
  def hibernate(mod, fun, state, parent, debug, args \\ []) do
    :proc_lib.hibernate(__MODULE__, :continue,
      [mod, fun, state, parent, debug, args])
  end

  ## :proc_lib api

  @doc false
  @spec init( nil | pid, nil | pid, name, module, args, [option]) ::
    no_return
  def init(mod, nil, parent, args, starter, opts) do
    init(mod, self(), parent, args, starter, opts)
  end

  def init(mod, name, nil, args, starter, opts) do
    init(mod, name, self(), args, starter, opts)
  end

  def init(mod, name, parent, args, nil, opts) do
    init(mod, name, parent, args, self(), opts)
  end

  def init(mod, name, parent, args, starter, opts) do
    try do
      do_init(mod, name, parent, args, starter, opts)
    else
      _ ->
        # Explicitly exit.
        exit(:normal)
    rescue
      exception ->
        base_stop(mod, parent, { exception, System.stacktrace() })
    catch
      # Turn throw into an exception.
      :throw, value ->
        exception = Base.UncaughtThrowError[actual: value]
        base_stop(mod, parent, { exception, System.stacktrace() })
      # Exits are not caught as they are an explicit intention to exit.
    end
  end

  @doc false
  @spec continue(module, atom, state, parent, Base.Debug.t, args) :: no_return
  def continue(mod, fun, state, parent, debug, args) do
    try do
      apply(mod, fun, [state, parent, debug] ++ args)
    else
      _ ->
        # Explicitly exit.
        exit(:normal)
    rescue
      exception ->
        base_stop(mod, parent, { exception, System.stacktrace() })
    catch
      # Turn throw into an exception.
      :throw, value ->
        exception = Base.UncaughtThrowError[actual: value]
        base_stop(mod, parent, { exception, System.stacktrace() })
      # Exits are not caught as they are an explicit intention to exit.
    end
  end

  ## utils

  @doc false
  @spec get_name() :: name
  def get_name(), do: Process.get(:"$name", self())

  @doc false
  @spec format(t) :: String.t
  def format(proc \\ get_name())

  def format(pid) when is_pid(pid) and node(pid) == node() do
    inspect(pid)
  end

  def format(pid) when is_pid(pid) do
    "#{inspect(pid)} on #{node(pid)}"
  end

  def format(name) when is_atom(name) do
    to_string(name)
  end

  def format({ :global, name }) do
    "#{inspect(name)} (global)"
  end

  def format({ name, node_name }) when node_name === node() do
    to_string(name)
  end

  def format({ name, node_name }) do
    "#{to_string(name)} on #{to_string(node_name)}"
  end

  def format({ :via, mod, name }) do
    "#{inspect(name)} (#{mod})"
  end

  ## internal

  ## init

  defp do_init(mod, name, parent, args, starter, opts) do
    case register(name) do
      :yes ->
        put_starter(starter)
        put_name(name)
        debug = new_debug(opts)
        mod.init(parent, debug, args)
      :no when starter === self() ->
        exit(:normal)
      :no ->
        reason = { :already_started, whereis(name) }
        :proc_lib.init_ack(starter, { :error, reason })
        exit(:normal)
    end
  end

  defp register(pid) when is_pid(pid), do: :yes

  defp register(name) when is_atom(name) do
    try do
      Process.register(self(), name)
    else
      :true ->
        :yes
    rescue
      ArgumentError ->
        :no
    end
  end

  defp register({ :global, name }) do
    :global.register_name(name, self())
  end

  defp register({ :via, mod, name }) when is_atom(mod) do
    mod.register_name(name, self())
  end

  defp put_name(name), do: Process.put(:"$name", name)

  defp put_starter(starter), do: Process.put(:"$starter", starter)

  defp get_starter(), do: Process.get(:"$starter", self())

  defp new_debug(opts) do
    case Keyword.get(opts, :debug, nil) do
      nil ->
        Base.Debug.new()
      debug_opts ->
        Base.Debug.new(debug_opts)
    end
  end

  ## stopping

  defp exit_type(:normal), do: :normal
  defp exit_type(:shutdown), do: :normal
  defp exit_type({ :shutdown, _reason }), do: :nornal
  defp exit_type(_reason), do: :abnormal

  defp unregister(name \\ get_name())
  defp unregister(pid) when is_pid(pid), do: nil
  defp unregister(name) when is_atom(name), do: Process.unregister(name)
  defp unregister({ :global, name }), do: :global.unregister_name(name)
  defp unregister({ :via, mod, name }), do: mod.unregister_name(name)

  defp print_debug(debug) do
    Base.Debug.print_log(debug)
    Base.Debug.print_stats(debug)
  end

  defp base_stop(mod, parent, reason) do
    report_base_stop(mod, parent, reason)
    exit(reason)
  end

  defp report_base_stop(mod, parent, { exception, stack }) do
    erl_format = '** ~ts ~ts is raising an exception~n   Module: ~ts~n   Pid: ~ts~n   Parent: ~ts~n   (~ts) ~ts~n~ts'
    args = [inspect(__MODULE__), format(), inspect(mod), inspect(self()),
      inspect(parent), inspect(elem(exception, 0)), exception.message,
      Exception.format_stacktrace(stack)]
    report(erl_format, args)
  end

  # Must guard against nil stack, Exception.format_stacktrace/1 will format its
  # own generated stacktrace with nil stack.
  defp report_init_stop(mod, parent, args, { exception, stack } = reason, event)
      when is_exception(exception) and stack !== nil do
    try do
      Exception.format_stacktrace(stack)
    else
      formatted_stack ->
        erl_format = '** ~ts ~ts is raising an exception~n   Arguments: ~ts~n   Pid: ~ts~n   Parent: ~ts~n   Last Event: ~ts~n   (~ts) ~ts~n~ts'
        args = [inspect(mod), format(), inspect(args), inspect(self()),
          inspect(parent), inspect(event), inspect(elem(exception, 0)),
          exception.message, formatted_stack]
        report(erl_format, args)
    rescue
      # Not a stacktrace!
      _ ->
        report_init_exit(mod, parent, args, reason, event)
    end
  end

  defp report_init_stop(mod, parents, args, reason, event) do
    report_init_exit(mod, parents, args, reason, event)
  end

  defp report_init_exit(mod, parent, args, reason, event) do
    erl_format = '** ~ts ~ts is terminating~n   Arguments: ~ts~n   Pid: ~ts~n   Parent: ~ts~n   Last Event: ~ts~n   EXIT: ~ts~n'
    args = [inspect(mod), format(), inspect(args), inspect(self()),
          inspect(parent), inspect(event), inspect(reason)]
    report(erl_format, args)
  end

  # Must guard against nil stack, Exception.format_stacktrace/1 will format its
  # own generated stacktrace with nil stack.
  defp report_stop(mod, state, parent, { exception, stack } = reason, event)
      when is_exception(exception) and stack !== nil do
    try do
      Exception.format_stacktrace(stack)
    else
      formatted_stack ->
        erl_format = '** ~ts ~ts is raising an exception~n   State: ~ts~n   Pid: ~ts~n   Parent: ~ts~n   Last Event: ~ts~n   (~ts) ~ts~n~ts'
        args = [inspect(mod), format(), inspect(state), inspect(self()),
          inspect(parent), inspect(event), inspect(elem(exception, 0)),
          exception.message, formatted_stack]
        report(erl_format, args)
    rescue
      # Not a stacktrace!
      _ ->
        report_exit(mod, state, parent, reason, event)
    end
  end

  defp report_stop(mod, state, parents, reason, event) do
    report_exit(mod, state, parents, reason, event)
  end

  defp report_exit(mod, state, parent, reason, event) do
    erl_format = '** ~ts ~ts is terminating~n   State: ~ts~n   Pid: ~ts~n   Parent: ~ts~n   Last Event: ~ts~n   EXIT: ~ts~n'
    args = [inspect(mod), format(), inspect(state), inspect(self()),
          inspect(parent), inspect(event), inspect(reason)]
    report(erl_format, args)
  end

  defp report(erl_format, args), do: :error_logger.error_msg(erl_format, args)

  ## communication

  defp call(process, target, label, request, timeout) do
    try do
      Process.monitor(process)
    rescue
      ArgumentError ->
        reason = case node() do
          # Can't connect to other nodes
          :"nonode@nohost" ->
            :noconnection
          # Target node is feature weak
          _other ->
            :nomonitor
        end
        raise Base.CallError, [target: target, process: process, label: label,
          request: request, reason: reason]
    else
      tag ->
        Process.send(process, { label, { self(), tag }, request }, [:noconnect])
        receive do
          { ^tag, response } ->
            Process.demonitor(tag, [:flush])
            response
          { :DOWN, ^tag, _, _, :noproc } ->
            raise Base.CallError, [target: target, process: process,
              label: label, request: request, reason: :noproc]
          { :DOWN, ^tag, _, _, :noconnection } ->
            raise Base.CallError, [target: target, process: process,
              label: label, request: request, reason: :noconnection]
          { :DOWN, ^tag, _, _, reason } ->
            raise Base.CallError, [target: target, process: process,
              label: label, request: request, reason: { :EXIT, reason }]
        after
          timeout ->
            Process.demonitor(tag, [:flush])
            raise Base.CallError, [target: target, process: process,
              label: label, request: request, reason: :timeout]
        end
    end
  end

  defp cast(process, msg) do
    try do
      Process.send(process, msg, [:noconnect])
    else
      :noconnect ->
        Process.spawn(Process, :send, [process, msg])
        :ok
      :ok ->
        :ok
    rescue
      _exception ->
        :ok
    end
  end

end
