defmodule Core.Debug.Supervisor do
  @moduledoc false

  use Supervisor.Behaviour

  ## api

  def start_link, do: :supervisor.start_link(__MODULE__, nil)

  ## :supervisor api

  def init(nil) do
    Core.Debug.ensure_table()
    supervise([], strategy: :one_for_one)
  end

end
