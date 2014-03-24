defmodule Base.Behaviour do
  @moduledoc """
  This module is a convenience module for adding the `Base` behaviour and
  requiring the `Base.Debug` module (for using the `Base.Debug.event/2 macro).

  ## Examples

      defmodule Base.HelloWorld do

        use Base.Behaviour

        @spec start_link() :: { :ok, pid }
        def start_link(), do: Base.start_link(__MODULE__, nil)

        def init(_parent, _debug, nil) do
          Base.init_ack()
          IO.puts("Hello World!")
        end

      end

      defmodule Base.Fn do

        use Base.Behaviour

        @spec start_link((() -> any)) :: { :ok, pid }
        def start_link(fun), do: Base.start_link(__MODULE__, fun)

        @spec spawn_link((() -> any)) :: pid
        def spawn_link(fun), do: Base.spawn_link(__MODULE__, fun)

        def init(parent, debug, fun) when is_function(fun, 0) do
          Base.init_ack()
          try do
            fun.()
          rescue
            exception ->
              reason = { exception, System.stacktrace() }
              Base.stop(__MODULE__, fun, parent, debug, reason)
          catch
            :throw, value ->
              exception = Base.UncaughtThrowError[actual: value]
              reason = { exception, System.stacktrace() }
              Base.stop(__MODULE__, fun, parent, debug, reason)
          end
        end

      end

      defmodule Base.PingPong do

        @spec ping(Base.t) :: :pong
        def ping(process), do: Base.call(process, __MODULE__, :ping, 5000)

        @spec count(Base.t) :: non_neg_integer
        def count(process), do: Base.call(process, __MODULE__, :count, 5000)

        @spec close(Base.t) :: :ok
        def close(process), do: Base.call(process, __MODULE__, :close, 5000)

        @spec start_link() :: { :ok, pid }
        def start_link(), do: Base.start_link(__MODULE__, nil)

        def init(_parent, _debug, nil) do
          Base.init_ack()
          loop(0)
        end

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
              terminate(count)
          end
        end

        defp terminate(_count) do
          exit(:normal)
        end

      end

  """

  defmacro __using__(_options) do
    quote location: :keep do

      @behaviour Base
      require Base.Debug

      @doc false
      def init(_parent, _debug, _args) do
        Base.init_ignore()
      end

      defoverridable [init: 3]

    end
  end

end
