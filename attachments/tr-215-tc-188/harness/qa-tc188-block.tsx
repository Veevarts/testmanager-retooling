
describe("QA TC-188 · IM-1312 — rows opened one after another and rows that share a title", () => {
  /*
    Escrito por QA (TR-215), no por el autor. Dos huecos que los 8 specs del
    autor no cubren: cada uno abre UNA sola fila por visita, y todas sus filas
    tienen titulos distintos.
  */
  const rowA = buildSuggestion({
    id: "qa-pool-a",
    accountId: "qa-account-a",
    accountName: "QA Account Alpha",
    title: "QA shared title",
    description: "QA description of row A",
    score: 40,
  });
  const rowB = buildSuggestion({
    id: "qa-pool-b",
    accountId: "qa-account-b",
    accountName: "QA Account Beta",
    title: "QA shared title",
    description: "QA description of row B",
    score: 35,
  });
  const serve = (items: Task[]) =>
    vi.mocked(getTaskSuggestionPool).mockImplementation(async () => ({
      items,
      nextCursor: null,
      remaining: 0,
    }));
  const openPool = async (user: ReturnType<typeof setupUser>) => {
    const panel = await openSuggestedPanel(user);
    await user.click(within(panel).getByTestId("suggested-panel-view-all"));
    const pool = await screen.findByTestId("suggestion-pool-modal");
    await waitFor(() =>
      expect(pool.querySelector(`[data-task-id="${rowB.id}"]`)).toBeInTheDocument()
    );
    return pool;
  };
  const card = (pool: HTMLElement, id: string) =>
    pool.querySelector(`[data-task-id="${id}"]`) as HTMLElement;

  it("QA TC-188 · a second pool row opened after closing the first shows the second, then a panel card shows itself", async () => {
    serve([rowA, rowB]);
    expect(store.suggestions.map((t) => t.id)).not.toContain(rowA.id);
    expect(store.suggestions.map((t) => t.id)).not.toContain(rowB.id);
    const user = setupUser();
    render(<Host />);
    const pool = await openPool(user);

    await user.click(within(card(pool, rowA.id)).getByTestId("suggestion-details"));
    let detail = await screen.findByTestId("task-detail-modal");
    expect(detail).toHaveTextContent("QA Account Alpha");
    await user.click(within(detail).getByRole("button", { name: "Close" }));
    await waitFor(() => expect(screen.queryByTestId("task-detail-modal")).not.toBeInTheDocument());

    const back = await screen.findByTestId("suggestion-pool-modal");
    await user.click(within(card(back, rowB.id)).getByTestId("suggestion-details"));
    detail = await screen.findByTestId("task-detail-modal");
    expect(detail).toHaveTextContent("QA Account Beta");
    expect(detail).not.toHaveTextContent("QA Account Alpha");
    expect(within(detail).getByTestId("task-detail-description")).toHaveValue("QA description of row B");
    await user.keyboard("{Escape}");

    const again = await screen.findByTestId("suggestion-pool-modal");
    await user.click(within(again).getByRole("button", { name: "Close" }));
    await waitFor(() => expect(screen.queryByTestId("suggestion-pool-modal")).not.toBeInTheDocument());

    const panel = await openSuggestedPanel(user);
    await user.click(within(panel).getAllByTestId("suggestion-details")[0]);
    detail = await screen.findByTestId("task-detail-modal");
    expect(within(detail).getByTestId("task-detail-title")).toHaveValue(store.suggestions[0].title);
  });

  it("QA TC-188 · two pool rows with the same title open the account and description of the clicked one", async () => {
    serve([rowA, rowB]);
    const user = setupUser();
    render(<Host />);
    const pool = await openPool(user);

    await user.click(within(card(pool, rowB.id)).getByTestId("suggestion-title"));
    const detail = await screen.findByTestId("task-detail-modal");
    expect(detail).toHaveTextContent("QA Account Beta");
    expect(detail).not.toHaveTextContent("QA Account Alpha");
    expect(within(detail).getByTestId("task-detail-description")).toHaveValue("QA description of row B");
  });
});
