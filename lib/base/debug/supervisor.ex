defmodule Base.Debug.Supervisor do
  use Supervisor.Behaviour

  ## api

  def start_link, do: :supervisor.start_link(__MODULE__, nil)

  ## :supervisor api

  def init(nil) do
    Base.Debug.ensure_table()
    supervise([], strategy: :one_for_one)
  end

end
