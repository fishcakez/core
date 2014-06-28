defmodule Core.Sys do

  use Behaviour

  @doc """
  Returns the state of the process.
  """
  defcallback system_get_state(data) :: state

  @doc """
  Updates the state of the process.
  """
  defcallback system_update_state(data, update) :: { state, data }

  @doc """
  Returns all data about the process.
  """
  defcallback system_get_data(data) :: data

  @doc """
  Changes the data for use with a different version of a module.
  """
  defcallback system_change_data(data, module, vsn, extra) :: data

  @doc """
  Called when the process should re-enter it's loop after handling
  system messages.
  """
  defcallback system_continue(data, Core.parent, Core.Debug.t) :: no_return

  @doc """
  Called when the process should terminate after handling system
  messages, i.e. an exit signal was received from the parent process
  when the current process is trapping exits.
  """
  defcallback system_terminate(data, Core.parent, Core.Debug.t, any) ::
    no_return

  ## types

  @typep data :: any
  @typep state :: any
  @typep update :: ((data) -> { state, data })
  @typep vsn :: any
  @typep extra :: any
  @type status :: map

  ## exceptions

  defmodule CallbackError do

    defexception [action: nil, kind: nil, payload: nil, stacktrace: [],
        message: "callback failed"]

    def exception(opts) do
      action = opts[:action]
      kind = opts[:kind]
      payload = opts[:payload]
      stacktrace = Keyword.get(opts, :stacktrace, [])
      message = "failure in " <> format_action(action) <> "\n" <>
        format_reason(kind, payload, stacktrace)
      %Core.Sys.CallbackError{action: action, kind: kind, payload: payload,
        stacktrace: stacktrace, message: message}
    end

    defp format_action(nil), do: "unknown function"
    defp format_action(fun), do: inspect(fun)

    defp format_reason(kind, payload, stacktrace) do
      reason = Exception.format(kind, payload, stacktrace)
      "    " <> Regex.replace(~r/\n/, reason, "\n    ")
    end

  end

  defmodule CatchLevelError do

    defexception [level: nil, message: "catch level error"]

    def exception(opts) do
      level = Keyword.fetch!(opts, :level)
      %Core.Sys.CatchLevelError{level: level, message: format_message(level)}
    end

    defp format_message(0) do
      "process was not started by Core or did not use Core to hibernate"
    end
    # 3 levels is one extra catch
    defp format_message(level) when level >= 3 do
      "Core.Sys loop was not entered by a tail call, #{level-2} catch(es)"
    end
  end

  ## macros

  @doc """
  Macro to handle system messages but not receive any other messages.

  `mod.system_continue/3` or `mod.system_terminate/4` will return
  control of the process to `mod` after handling system messages.

  Should only be used as a tail call as it has no local return.
  """
  defmacro receive(mod, data, parent, debug) do
    parent_quote = quote do: parent_var
    extra = transform_receive(mod, data, parent_quote, debug)
    quote do
      parent_var = unquote(parent)
      receive do: unquote(extra)
    end
  end

  @doc """
  Macro to handle system messages and receive messages.

  `mod.system_continue/3` or `mod.system_terminate/4` will return
  control of the process to `mod` after handling system messages.

  Should only be used as a tail call as it has no local return.

  ## Examples

      use Core.Sys.Behaviour

      defp loop(data, parent, debug) do
        Core.Sys.receive(__MODULE__, data, parent, debug) do
          msg ->
            IO.puts(:stdio, inspect(msg))
            loop(data, parent, debug)
        after
          1000 ->
            terminate(data, parent, debug, timeout)
        end
      end

      def system_continue(data, parent, debug) do
        loop(data, parent, debug)
      end

      def system_terminate(_data, _parent, _debug, reason) do
        terminate(reason)
      end

      defp terminate(reason) do
        exit(reaosn)
      end

  """
  defmacro receive(mod, data, parent, debug, do: do_clauses) do
    parent_quote = quote do: parent_var
    extra = transform_receive(mod, data, parent_quote, debug)
    quote do
      parent_var = unquote(parent)
      receive do: unquote(extra ++ do_clauses)
    end
  end

  defmacro receive(mod, data, parent, debug, do: do_clauses,
      after: after_clause) do
    parent_quote = quote do: parent_var
    extra = transform_receive(mod, data, parent_quote, debug)
    quote do
      parent_var = unquote(parent)
      receive do: unquote(extra ++ do_clauses), after: unquote(after_clause)
    end
  end

  defmacrop default_timeout(), do: 5000

  ## debug api

  @doc """
  Pings an OTP process to see if it is responsive to system messages.
  Returns `:pong` on success.
  """
  @spec ping(Core.t, timeout) :: :pong
  def ping(process, timeout \\ default_timeout()) do
    { :error, { :unknown_system_msg, :ping } } = call(process, :ping, timeout)
    :pong
  end

  @doc """
  Suspends an OTP process so that it can only handle system messages.
  """
  @spec suspend(Core.t, timeout) :: :ok
  def suspend(process, timeout \\ default_timeout()) do
    call(process, :suspend, timeout)
  end

  @doc """
  Resumes an OTP process that has been system suspended.
  """
  @spec resume(Core.t, timeout) :: :ok
  def resume(process, timeout \\ default_timeout()) do
    call(process, :resume, timeout)
  end

  @doc """
  Returns the state of an OTP process.
  """
  @spec get_state(Core.t, timeout) :: state
  def get_state(process, timeout \\ default_timeout()) do
    state_call(process, :get_state, timeout)
  end

  @doc """
  Sets the state of an OTP process.
  """
  @spec set_state(Core.t, state, timeout) :: :ok
  def set_state(process, state, timeout \\ default_timeout()) do
    update = fn(_old_state) -> state end
    ^state = state_call(process, { :replace_state, update }, timeout)
    :ok
  end

  @doc """
  Updates the state of an OTP process.
  Returns the updated state.
  """
  @spec update_state(Core.t, update, timeout) :: state
  def update_state(process, update, timeout \\ default_timeout()) do
    state_call(process, { :replace_state, update }, timeout)
  end

  @doc """
  Returns status information about an OTP process.

  This function will return alot of information, including the process
  dictionary of the target process.
  """
  @spec get_status(Core.t, timeout) :: status
  def get_status(process, timeout \\ default_timeout()) do
    call(process, :get_status, timeout)
      |> parse_status()
  end

  @doc """
  Returns the data held about an OTP process.

  This function will return any data held about a process. In many cases
  this will return the same as `get_state/2`.
  """
  @spec get_data(Core.t, timeout) :: data | nil
  def get_data(process, timeout \\ default_timeout()) do
    get_status(process, timeout)
      |> Dict.get(:data)
  end

  @doc """
  Change the data of an OTP process due to a module version change.

  Can only be used on system suspended processes.
  """
  @spec change_data(Core.t, module, vsn, extra, timeout) :: :ok
  def change_data(process, mod, oldvsn, extra, timeout \\ default_timeout()) do
    case state_call(process, { :change_code, mod, oldvsn, extra }, timeout) do
      :ok ->
        :ok
      { :error, {:EXIT, reason } } ->
        raise Core.Sys.CallbackError, [kind: :exit, payload: reason]
      # direct :sys module did not return { :ok, data }
      { :error, other } ->
        raise Core.Sys.CallbackError,
          [kind: :error, payload: other]
    end
  end

  @doc """
  Returns any logged events created by an OTP process.

  The oldest event is at the head of the list.
  """
  @spec get_log(Core.t, timeout) :: [Core.Debug.event]
  def get_log(process, timeout \\ default_timeout()) do
    debug_call(process, { :log, :get }, timeout)
      |> Core.Debug.log_from_raw()
  end

  @doc """
  Prints any logged events created by an OTP process to `:stdio`.
  """
  @spec print_log(Core.t, timeout) :: :ok
  def print_log(process, timeout \\ default_timeout()) do
    raw_log = debug_call(process, { :log, :get }, timeout)
    Core.Debug.write_raw_log(:stdio, process, raw_log)
  end

  @doc """
  Sets the number of logged events to store for an OTP process.
  """
  @spec set_log(Core.t, non_neg_integer | boolean, timeout) :: :ok
  def set_log(process, max, timeout \\ default_timeout())

  def set_log(process, 0, timeout) do
    debug_call(process, { :log, false }, timeout)
  end

  def set_log(process, max, timeout) when is_integer(max) and max > 0 do
    debug_call(process, { :log, { :true, max  }}, timeout)
  end

  @doc """
  Set the file to log events to for an OTP process.
  `nil` will turn off logging events to file.
  """
  @spec set_log_file(Core.t, Path.t | nil, timeout) :: :ok
  def set_log_file(process, path, timeout \\ default_timeout())

  def set_log_file(process, nil, timeout) do
    debug_call(process, { :log_to_file, false }, timeout)
  end

  def set_log_file(process, path, timeout) do
    case debug_call(process, { :log_to_file, path }, timeout) do
      :ok ->
        :ok
      { :error, :open_file } ->
        raise ArgumentError, message: "could not open file: #{inspect(path)}"
    end
  end

  @doc """
  Returns stats about an OTP process if it is collecting statistics.
  Otherwise returns `nil`.
  """
  @spec get_stats(Core.t, timeout) :: Core.Debug.stats | nil
  def get_stats(process, timeout \\ default_timeout()) do
    debug_call(process, { :statistics, :get }, timeout)
      |> Core.Debug.stats_from_raw()
  end

  @doc """
  Prints statistics collected by an OTP process to `:stdio`.
  """
  @spec print_stats(Core.t, timeout) :: :ok
  def print_stats(process, timeout \\ default_timeout()) do
    stats = get_stats(process, timeout)
    Core.Debug.write_stats(:stdio, process, stats)
  end

  @doc """
  Sets whether an OTP process collects statistics or not.
  `true` will collect statistics.
  `false` will not collect statistics.
  """
  @spec set_stats(Core.t, boolean, timeout) :: :ok
  def set_stats(process, flag, timeout \\ default_timeout())
      when is_boolean(flag) do
    debug_call(process, { :statistics, flag }, timeout)
  end

  @doc """
  Sets whether an OTP process should print events to `:stdio` as they occur.
  `true` will print events.
  `false` will not print events.
  """
  @spec set_trace(Core.t, boolean, timeout) :: :ok
  def set_trace(process, flag, timeout \\ default_timeout())
      when is_boolean(flag) do
    debug_call(process, { :trace, flag }, timeout)
  end

  @doc """
  Sets a hook to act on events for an OTP process.
  Setting the hook state to `nil` will remove the hook.
  """
  @spec set_hook(Core.t, Core.Debug.hook, Core.Debug.hook_state | nil,
      timeout) :: :ok
  def set_hook(process, hook, state, timeout \\ default_timeout())

  def set_hook(process, hook, nil, timeout) when is_function(hook, 3) do
    debug_call(process, { :remove, hook }, timeout)
  end

  def set_hook(process, hook, state, timeout) when is_function(hook, 3) do
    debug_call(process, { :install, { hook, state } }, timeout)
  end

  ## receive macro api

  @doc false
  @spec message(__MODULE__, data, Core.parent, Core.Debug.t, any, Core.from) ::
    no_return
  def message(mod, data, parent, debug, msg, from) do
    :sys.handle_system_msg(msg, from, parent, __MODULE__, debug, [mod | data])
  end

  ## :sys api

  def system_continue(parent, debug, [mod | data]) do
    continue(mod, :system_continue, data, parent, debug)
  end

  @doc false
  def system_terminate(reason, parent, _debug, [mod | data]) do
    continue(mod, :system_terminate, data, parent, [reason])
  end

  @doc false
  def system_get_state([mod | data]) do
    try do
      mod.system_get_state(data)
    else
      state ->
        { :ok, state }
    rescue
      # Callback failed in a callback of mod
      exception in [Core.Sys.CallbackError] ->
        raise exception
    catch
      kind, payload ->
        raise Core.Sys.CallbackError,
          action: :erlang.make_fun(mod, :system_get_state, 1),
          kind: kind, payload: payload, stacktrace: System.stacktrace()
    end
  end

  @doc false
  def system_replace_state(replace, [mod | data]) do
    try do
      { _state, _data} = mod.system_update_state(data, replace)
    else
      { state, data } ->
        { :ok, state, [mod | data] }
    rescue
      # Callback failed in a callback of mod
      exception in [Core.Sys.CallbackError] ->
        raise exception
    catch
      kind, payload ->
        raise Core.Sys.CallbackError,
          action: :erlang.make_fun(mod, :system_update_state, 2),
          kind: kind, payload: payload, stacktrace: System.stacktrace()
    end
  end

  @doc false
  def format_status(_type, [_pdict, sys_status, parent, debug, [mod | data]]) do
    base_status = format_base_status(sys_status, parent, mod, debug)
    try do
      mod.system_get_data(data)
    else
      mod_data ->
        base_status ++ [{ :data, [{ 'Module data', mod_data }] }]
    rescue
      exception in [Core.Sys.CallbackError] ->
        format_status_error(base_status, data, exception)
    catch
      kind, payload ->
        exception = Core.Sys.CallbackError.exception([
          action: :erlang.make_fun(mod, :system_get_data, 1),
          kind: kind, payload: payload, stacktrace: System.stacktrace()])
        format_status_error(base_status, data, exception)
    end
  end

  @doc false
  def system_code_change([mod | data], change_mod, oldvsn, extra) do
    try do
      mod.system_change_data(data, change_mod, oldvsn, extra)
    else
      data ->
        { :ok, [mod | data] }
    rescue
      # Callback failed in a callback of mod.
      exception in [Core.Sys.CallbackError] ->
        code_change_error(exception)
    catch
      kind, payload ->
        exception = Core.Sys.CallbackError.exception([
          action: :erlang.make_fun(mod, :system_change_data, 4),
          kind: kind, payload: payload, stacktrace: System.stacktrace()])
        code_change_error(exception)
    end
  end

  ## internal

  ## receive

  defp transform_receive(mod, data, parent, debug) do
    quote do
      { :EXIT, ^unquote(parent), reason } ->
        unquote(mod).system_terminate(unquote(data), unquote(parent),
          unquote(debug), reason)
      { :system, from, msg } ->
        Core.Sys.message(unquote(mod), unquote(data), unquote(parent),
          unquote(debug), msg, from)
    end
  end

  ## calls

  defp call(process, request, timeout) do
    Core.call(process, :system, request, timeout)
  end

  defp state_call(process, request, timeout) do
    case call(process, request, timeout) do
      { :ok, result } ->
        result
      { :error, { :unknown_system_msg, { :change_code, _, _, _ } } } ->
        raise ArgumentError, message: "#{Core.format(process)} is running"
      { :error, { :unknown_system_msg, _request } } ->
        raise ArgumentError, message: "#{Core.format(process)} is suspended"
      :ok ->
        :ok
      # exception raised by this module, raise it.
      { :error, { :callback_failed, { __MODULE__, _ },
            { :error, %Core.Sys.CallbackError{} = exception } } } ->
        raise exception
      # raise in a direct :sys module
      { :error, { :callback_failed, action, { kind, payload } } } ->
        raise Core.Sys.CallbackError, action: action, kind: kind,
          payload: payload
      state ->
        state
    end
  end

  defp debug_call(process, request, timeout) do
    case call(process, { :debug, request }, timeout) do
      :ok ->
        :ok
      { :ok, result } ->
        result
      { :error, _reason } = error ->
        error
    end
  end

  ## :sys api

  defp parse_status({ :status, pid, { :module, __MODULE__ },
        [pdict, sys_status, parent, _debug, status]}) do
    status_data = get_status_data(status)
    case get(status_data, 'Module error') do
      nil ->
        parse_status_data(pid, __MODULE__, pdict, sys_status, parent,
          status_data)
      { :callback_failed, { __MODULE__, _ }, { :error, exception } } ->
        raise exception
    end
  end

  defp parse_status({ :status, pid, { :module, mod },
        [pdict, sys_status, parent, _debug, status]}) do
    status_data = get_status_data(status)
    parse_status_data(pid, mod, pdict, sys_status, parent, status_data)
  end

  defp get_status_data(status) do
    try do
      data = Keyword.get_values(status, :data)
      # special case for :gen_event (or similar direct :sys)
      items = Keyword.get_values(status, :items)
      List.flatten([items, data])
    rescue
      # not formed as expected, pass whole status as state. Will be used
    # as data term later.
      exception ->
        IO.puts(:user, inspect(exception))
        [{ 'State', status }]
    end
  end

  defp parse_status_data(pid, mod, pdict, sys_status, parent, status_data) do
    name = get(status_data, 'Name', pid)
    log = parse_status_log(status_data)
    stats = parse_status_stats(status_data)
    mod2 = get(status_data, 'Module', mod)
    mod_data = get_mod_data(mod, status_data)
    %{ name: name, log: log, stats: stats, module: mod2, data: mod_data,
       pid: pid, dictionary: pdict, sys_status: sys_status, parent: parent }
  end

  defp parse_status_log(status_data) do
    case get(status_data, 'Logged events', []) do
      [] ->
        []
      { _max, rev_raw_log } ->
        Enum.reverse(rev_raw_log)
          |> Core.Debug.log_from_raw()
    end
  end

  defp parse_status_stats(status_data) do
    get(status_data, 'Statistics', :no_statistics)
      |> Core.Debug.stats_from_raw()
  end

  defp get_mod_data(__MODULE__, status_data) do
    get(status_data, 'Module data')
  end

  defp get_mod_data(:gen_fsm, status_data) do
    state_name = get(status_data, 'StateName')
    state_data = get(status_data, 'StateData')
    { state_name, state_data }
  end

  defp get_mod_data(:gen_event, status_data) do
    to_data = fn({ :handler, mod, id, state, _sup }) -> { mod, id, state} end
    get(status_data, 'Installed handlers')
      |> Enum.map(to_data)
  end

  defp get_mod_data(_mod, status_data) do
    get(status_data, 'State', status_data)
  end

  defp format_base_status(sys_status, parent, mod, debug) do
    header = String.to_char_list("Status for #{inspect(mod)} #{Core.format()}")
    log = get_status_log(debug)
    stats = get_status_stats(debug)
    data = [{ 'Status', sys_status }, { 'Parent', parent },
      { 'Name', Core.get_name() }, { 'Logged events', log },
      { 'Statistics', stats }, { 'Module', mod }]
    [{ :header, header }, { :data, data }]
  end

  defp get_status_log(debug) do
    try do
      # How gen_* returns format_status log
      :sys.get_debug(:log, debug, [])
    rescue
      _exception ->
        []
    end
  end

  defp get_status_stats(debug) do
    try do
      Core.Debug.get_raw_stats(debug)
    rescue
      _exception ->
        :no_statistics
    end
  end

  defp format_status_error(base_status, mod_data, exception) do
    reason = { :callback_failed, { __MODULE__, :format_status },
      { :error, exception } }
    mod_status = [{ :data,
        [{ 'Module data', mod_data }, { 'Module error', reason }] }]
    base_status ++ mod_status
  end

  defp code_change_error(exception) do
    # Does not match { :ok, data } causing { :error, { :callback_failed, ..}} to
    # be returned by :sys. This is the same form as the replace/get_state error
    # message returned in 17.0 final. Therefore even though it is handled
    # differently in :sys, to Core.Sys modules it will appear to be handled the
    # same as replace/get_state.
    { :callback_failed, { __MODULE__, :system_code_change },
      { :error, exception } }
  end

  defp continue(mod, fun, data, parent, debug, args \\ []) do
    case Process.info(self(), :catchlevel) do
      # Assume :proc_lib catch but no Core catch due to hibernation.
      { :catchlevel, 1 } ->
        # Use Core to re-add Core catch for logging exceptions.
        Core.continue(mod, fun, data, parent, debug, args)
      # Assume :proc_lib catch and Core catch, i.e. no hibernation.
      { :catchlevel, 2 } ->
        apply(mod, fun, [data, parent, debug] ++ args)
      # Either not a Core/:proc_lib process OR
      # Core.Sys.receive/4 macro was used inside a catch.
      { :catchlevel, level } ->
        try do
          raise Core.Sys.CatchLevelError, level: level
        rescue
          exception ->
            # Hibernation didn't occur (level would be 1) so generate a
            # stacktrace (and exception), which hopefully will be logged by mod.
            reason = { exception, System.stacktrace()}
            # Use Core to add Core catch which may log an exception if one is
            # raised. If we have two levels (or more!) of the Core catch an
            # exception will only be logged once.
            Core.continue(mod, :system_terminate, data, parent, debug,
              [reason])
        end
    end
  end

  ## util

  defp get(list, key, default \\ nil) do
    case List.keyfind(list, key, 0, nil) do
      nil ->
        default
      { _key, value } ->
        value
    end
  end

end
