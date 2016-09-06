defmodule SimpleHash.Sup do
  use Supervisor
  def start_link do
    # riak_core appends _sup to the application name.
    Supervisor.start_link(__MODULE__, [], [name: :simple_hash_sup])
  end
  def init(_args) do
    # riak_core appends _master to 'SimpleHash.Vnode'
    children = [
      worker(:riak_core_vnode_master, [SimpleHash.Vnode], id: SimpleHash.Vnode_master_worker)
    ]
    supervise(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 10)
  end
end
