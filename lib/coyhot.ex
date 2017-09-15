defmodule Coyhot do

  @doc """
  determine how much time is necessary between tasks
  """
  @callback ticker(informations :: term) :: integer


  @doc """
  task function name
  """
  @callback handle_task(data :: term, informations :: term) :: :noreply

  @doc """
  function that fetch data to process for each tasks
  """
  @callback tasks_data(informations :: term) :: List

  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Coyhot

      use GenServer

      def handle_task(_, _) do
        raise "attempt to call handle_task(data) but clause was not provided"
      end

      def tasks_data(_) do
        raise "attempt to call tasks_data() but clause was not provided"
      end

      def ticker(_) do
        raise "attempt to call ticker() but clause was not provided"
      end

      def init([task_supervisor, use_ticker, informations]) do
        state =
          %{
            task_supervisor: task_supervisor,
            tasks: [],
            use_ticker: use_ticker,
            has_ticked: false,
            informations: informations
          }
          |> schedule_tasks

        {:ok, state}
      end

      def handle_info({:DOWN, mref, _, _pid, _reason}, %{tasks: tasks} = state) do
        state = state |> handle_task_finished(mref)
        {:noreply, state}
      end

      def handle_info({task_ref, result}, state) when is_reference(task_ref) do
        state = state |> handle_task_finished(task_ref)
        {:noreply, state}
      end

      def handle_info(:ticker, %{tasks: []} = state) do
        state =
          state
          |> schedule_tasks
        {:noreply, state}
      end

      def handle_info(:ticker, state) do
        state = %{state | has_ticked: true}
        {:noreply, state}
      end

      def handle_task_finished(state, ref) do
        state
        |> remove_task(ref)
        |> schedule_if_done
      end

      defp schedule_tasks(state) do
        state
        |> start_tasks()
        |> start_ticking()
      end

      defp start_tasks(%{task_supervisor: supervisor, informations: informations} = state) do
        tasks = tasks_data(informations)
               |> Enum.map(&start_task(supervisor, &1, informations))
               |> Enum.map(fn(task) -> task.ref end)
        %{state | tasks: tasks}
      end

      defp start_task(task_supervisor, data, informations) do
        Task.Supervisor.async_nolink(
          task_supervisor, fn() ->
            handle_task(data, informations)
          end
        )
      end

      defp start_ticking(%{use_ticker: true, informations: informations} = state) do
        next_tick = ticker(informations)
        Process.send_after(self(), :ticker, next_tick)
        %{state | has_ticked: false}
      end
      defp start_ticking(state), do: state

      defp remove_task(%{tasks: tasks} = state, task_ref) do
        %{state | tasks: tasks |> List.delete(task_ref)}
      end

      defp schedule_if_done(%{tasks: [], use_ticker: false} = state) do
        state |> schedule_tasks
      end

      defp schedule_if_done(%{tasks: [], use_ticker: true, has_ticked: true} = state) do
        state |> schedule_tasks
      end

      defp schedule_if_done(state), do: state

      defoverridable [handle_task: 2, tasks_data: 1, ticker: 1]
    end
  end
end
