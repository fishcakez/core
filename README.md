# Base
Library for implementing OTP processes natively in Elixir.

Provides utility functions and macros to implement 100% OTP compliant
processes with 100%\* compatibility with all Erlang/OTP modules and tools.

\* The getting and replacing of process state debug functions will not
behave idenitically with `:sys` until 17.0 final is released.

# Installing
```
git clone https://github.com/fishcakez/base.git
cd base
mix do deps.get, docs, compile
```

# Hello World
Start a process that prints "Hello World" to `:stdio`.
```elixir
defmodule HelloWorld do

  use Base.Behaviour

  def start_link(), do: start_link(__MODULE__, nil)

  def init(_parent, _debug, _args) do
    IO.puts("Hello World")
    # Base.init_ack/0 will cause start_link/0 to return { :ok, self() }. If this
    # function is never called start_link will block until this process exits.
    Base.init_ack()
    exit(:normal)
  end

end
```

# Features
* Call processes (including Erlang/OTP's `:gen_server` processes) with
  very detailed exception messages.
* Asynchronous and synchronous process initiation (with name registration).
* Automatic logging of un-rescued exceptions.
* System calls that work with any OTP compliant process.
* Receive macro to handle system messages.
* Supports progressive enhancement of OTP features: system message
  automatically handled until you want to change the default behaviour.

# Call a :gen\_server registered as :server
```elixir
Base.call(:$gen_call, :server, request, timeout)
```
If `:server` does not exist:
```
** (Base.CallError) $gen_call to server failed: no process associated with that name
```

# Basic Ping Server
Starts a process that can be pinged.
```elixir
defmodule PingPong do

  use Base.Behaviour

  @spec ping(Base.t) :: :pong
  def ping(process), do: Base.call(process, __MODULE__, :ping, 5000)

  @spec count(Base.t) :: non_neg_integer
  def count(process), do: Base.call(process, __MODULE__, :count, 5000)

  @spec close(Base.t) :: :ok
  def close(process), do: Base.call(process, __MODULE__, :close, 5000)

  @spec start_link() :: { :ok, pid }
  def start_link() do
    Base.start_link(__MODULE__, nil,)
  end

  # Base api

  def init(_parent, _debug, _args) do
    Base.init_ack()
    loop(0)
  end

  ## Internal

  defp loop(count) do
    receive do
      { __MODULE__, from, :ping } ->
        Base.reply(from, :pong)
        loop(count + 1)
      { __MODULE__, from, :count } ->
        Base.reply(from, count)
        loop(count)
      { __MODULE__, from, :close } ->
        Base.reply(from, :ok)
        terminate(:normal)
    end
  end

  defp terminate(reason) do
    exit(reason)
  end

end
```

# Advanced Ping Server
Starts a process that can be pinged, live debugged and live code
upgraded.

For example `Base.Sys.set_state(pid, 0)` will reset the `count` to `0`.
```elixir

defmodule PingPong do

  use Base.Behaviour
  use Base.Sys.Behaviour

  @spec ping(Base.t) :: :pong
  def ping(process), do: Base.call(process, __MODULE__, :ping, 5000)

  @spec count(Base.t) :: non_neg_integer
  def count(process), do: Base.call(process, __MODULE__, :count, 5000)

  @spec close(Base.t) :: :ok
  def close(process), do: Base.call(process, __MODULE__, :close, 5000)

  # die/1 will print alot of information because the exit reason is abnormal.
  @spec die(Base.t) :: :ok
  def die(process), do: Base.call(process, __MODULE__, :die, 5000)

  @spec start_link() :: { :ok, pid }
  def start_link() do
    Base.start_link(nil, __MODULE__, nil,
      [{ :debug, [{ :log, 10 }, { :stats, true }] }])
  end

  ## Base api

  def init(parent, debug, _args) do
    Base.init_ack()
    loop(0, parent, debug)
  end

  ## Base.Sys (minimal) api

  def system_continue(count, parent, debug), do: loop(count, parent, debug)

  def system_terminate(count, parent, debug, reason) do
    terminate(count, parent, debug, reason)
  end

  ## Internal

  defp loop(count, parent, debug) do
    Base.Sys.receive(__MODULE__, count, parent, debug) do
      { __MODULE__, from, :ping } ->
        # It is not required to record events using `Base.Debug.event/1` but is
        # a useful debug feature that is compiled to a no-op in production.
        debug = Base.Debug.event(debug, { :in, :ping, elem(from, 0) })
        Base.reply(from, :pong)
        debug = Base.Debug.event(debug, { :out, :pong, elem(from, 0) })
        count = count + 1
        debug = Base.Debug.event(debug, { :count, count })
        loop(count, parent, debug)
      { __MODULE__, from, :count } ->
        debug = Base.Debug.event(debug, { :in, :count, elem(from, 0) })
        Base.reply(from, count)
        debug = Base.Debug.event(debug, { :out, count, elem(from, 0) })
        loop(count, parent, debug)
      { __MODULE__, from, :close } ->
        debug = Base.Debug.event(debug, { :in, :close, elem(from, 0) })
        Base.reply(from, :ok)
        debug = Base.Debug.event(debug, { :out, :ok, elem(from, 0)  })
        terminate(count, parent, debug, :normal)
      { __MODULE__, from, :die } ->
        debug = Base.Debug.event(debug, { :in, :die, elem(from, 0) })
        Base.reply(from, :ok)
        debug = Base.Debug.event(debug, { :out, :ok, elem(from, 0)  })
        terminate(count, parent, debug, :die)
    end
  end

  defp terminate(count, parent, debug, reason) do
    event = { :EXIT, reason }
    debug = Base.Debug.event(debug, event)
    Base.stop(__MODULE__, count, parent, debug, reason, event)
  end

end
```





