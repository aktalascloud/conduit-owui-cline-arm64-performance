const changes = new WeakMap<object, Set<string>>();
// Restricted model update on the already authenticated, selected session.
export async function changeSessionModel(ctx: any, peer: any, args: any, deps: any) {
  const sessionId = peer.selectedSessionId;
  if (!ctx.cline || !sessionId || args?.sessionId !== sessionId || peer.sending) throw new Error("Session unavailable or busy");
  const provider = args.provider, model = args.model;
  if (typeof provider !== "string" || typeof model !== "string" || model.length > 512) throw new Error("Invalid model");
  const pending = changes.get(ctx) ?? new Set<string>();
  changes.set(ctx,pending);
  if (pending.has(sessionId)) throw new Error("Session busy");
  pending.add(sessionId);
  try {
  const session = await ctx.cline.get(sessionId);
  if (!session || ["running", "starting", "stopping"].includes(session.status)) throw new Error("Session busy");
  const currentProvider = session.providerId ?? session.provider ?? session.metadata?.providerId;
  // A provider change needs a rebuilt provider client; never retain another provider's credentials.
  if (provider !== currentProvider) throw new Error("Choose a model from this session's provider");
  const catalog = await deps.models(provider, deps.settings.getProviderConfig(provider, {includeKnownModels: false}));
  if (!catalog.models.some((m: any) => m.id === model && (!m.operation || m.operation === "language"))) throw new Error("Model unavailable");
  if (peer.selectedSessionId !== sessionId || peer.sending) throw new Error("Session changed");
  try {
    await ctx.cline.updateSessionConnection(sessionId, {modelId: model});
  } catch (error) {
    if (!(error instanceof Error) || !/^session not found:/i.test(error.message)) throw error;
    // Rehydrate the same dormant session without a prompt, fork, workspace restore or history replay.
    const messages = await ctx.cline.readMessages(sessionId);
    if (!messages.length || peer.selectedSessionId !== sessionId || peer.sending) throw new Error("Session unavailable");
    const resume = deps.resume(session, {initialMessages: messages});
    resume.config.sessionId = sessionId;
    resume.toolPolicies = {"*": {autoApprove: false}};
    const started = await ctx.cline.start(resume);
    if (started.sessionId !== sessionId) throw new Error("Session identity changed");
    await ctx.cline.updateSessionConnection(sessionId, {modelId: model});
    if (JSON.stringify(await ctx.cline.readMessages(sessionId)) !== JSON.stringify(messages)) throw new Error("History verification failed");
  }
  const verified = await ctx.cline.get(sessionId);
  if ((verified?.modelId ?? verified?.model) !== model) throw new Error("Model update not confirmed");
  return {sessionId, provider, model};
  } finally { pending.delete(sessionId); }
}
