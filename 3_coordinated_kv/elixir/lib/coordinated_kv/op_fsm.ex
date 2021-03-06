defmodule CoordinatedKV.OpFSM do
  require Logger
  @behaviour :gen_fsm
  def start_link(req_id, from, op, key, n, w) do
    :gen_fsm.start_link(__MODULE__, [req_id, from, op, key, n, w], [])
  end

  def op(op, key, n, w) do
  	req_id = req_id()
  	CoordinatedKV.OpFSM.Sup.start_op_fsm([req_id, self(), op, key, n, w])
  	{:ok, req_id}
  end

  # FSM callbacks
  def init([req_id, from, op, key, n, w]) do
    Logger.info("FSM #{req_id} ('#{inspect op}') spawning: #{n} target vnodes (n), of which #{w} must reply for success (r/w)")
    state_data = %{
      req_id: req_id,
      from: from,
      n: n, w: w,
      num_w: 0,
      op: op,
      key: key,
      accum: [],
      preflist: []
    }
    {:ok, :prepare, state_data, 0}
  end

  # FSM states
  def prepare(:timeout, %{n: n, key: key, req_id: req_id, op: op}=state_data) do
    Logger.info("FSM #{req_id} ('#{inspect op}') hashing ring key #{inspect key} and asking for preference list with #{n} members")
    doc_idx = :riak_core_util.chash_key(key)
    pref_list = :riak_core_apl.get_apl(doc_idx, n, CoordinatedKV.Service)
    state_data = %{state_data | preflist: pref_list}
    {:next_state, :execute, state_data, 0}
  end

  def execute(:timeout, %{req_id: req_id, op: op, preflist: pref_list}=state_data) do
    Logger.info("FSM #{req_id} ('#{inspect op}') sending command to preference list members")
    command = {req_id, op}
    :riak_core_vnode_master.command(pref_list, command, {:fsm, :undefined, self()}, CoordinatedKV.Vnode_master)
    {:next_state, :waiting, state_data}
  end

  # this gets triggered by send_event in reply() from :riak_core_vnode_master
  def waiting({req_id, resp}, %{from: from, num_w: num_w, w: w, accum: accum, op: op}=state_data) do
    num_w = num_w + 1
    Logger.info("FSM #{req_id} ('#{inspect op}') received response number #{num_w} of #{w}")
    accum = [resp|accum]
    state_data = %{state_data | num_w: num_w, accum: accum}
    if num_w === w do
      send from, {req_id, accum}
      {:stop, :normal, :state_data}
    else
      {:next_state, :waiting, state_data}
    end
  end

  # gen_fsm callbacks
  def handle_info(info, _state_name, state_data) do
    Logger.warn("got an unexpected info: #{inspect [info, state_data]}")
    {:stop, :badmsg, state_data}
  end

  def handle_event(event, _state_name, state_data) do
    Logger.warn("got an unexpected event: #{inspect [event, state_data]}")
    {:stop, :badmsg, state_data}
  end

  def handle_sync_event(event, _from, _state_name, state_data) do
    Logger.warn("got an unexpected sync event: #{inspect [event, state_data]}")
    {:stop, :badmsg, state_data}
  end

  def terminate(_reason, _sn, _sd) do
    :ok
  end

  def code_change(_oldvsn, state_name, state_data, _extra) do
    {:ok, state_name, state_data}
  end

  defp req_id() do
    :erlang.unique_integer
  end
end
