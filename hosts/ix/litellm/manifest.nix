# models.json — the public, unauthenticated manifest an agent can be pointed at to
# auto-configure a harness against this proxy.
#
# Shaped like models.dev (https://models.dev/api.json), which is what opencode and
# Pi already consume, so a harness-configuring agent has the best chance of mapping
# it without bespoke instructions.
#
# Generated from ./models.nix, the same definition that produces config.yaml. That
# is the whole point: a hand-maintained second copy of the model list is exactly
# how the DeepSeek prices came to be wrong, and this file must not become one.
#
# WHY THIS EXISTS AT ALL, given the proxy already serves /model_group/info:
# that endpoint reports supported_openai_params from LiteLLM's internal model map,
# which knows nothing about our allowed_openai_params allowlist. It therefore
# advertises reasoning_effort as unsupported on every openai/-prefixed model here,
# which is the opposite of the truth. It also omits cache-read pricing entirely,
# and has no way to express per-provider reasoning ladders or the route-level
# caveats (zen's chat/completions shim silently dropping vision and json_schema).
#
# CONTENTS ARE PUBLIC. No credentials: api_key values in config.yaml are
# `os.environ/NAME` pointers and are not reproduced here, and neither are the
# upstream api_base hostnames. What this does disclose is the model lineup, the
# limits, and what we believe each model costs.
{ lib }:

let
  src = import ./models.nix { inherit lib; };

  names = map (m: m.model_name) src.modelList;
  harnessNames = lib.attrNames src.harness;

  # Models defined above with no harness decision recorded.
  undecided = lib.subtractLists harnessNames names;
  # Harness entries whose model no longer exists.
  orphaned = lib.subtractLists names harnessNames;

  # Per-token -> per-1M, rounded to 8 decimals. Without the rounding, floating
  # point turns $0.10/1M into 0.09999999999999999 in the published JSON —
  # numerically harmless but it reads as a mistake in a file agents consume.
  # 8 places is enough for the smallest real figure here (gemini's 0.0208333
  # cache-write rate) without reintroducing artefacts.
  perMillion = c: builtins.floor ((c * 1.0e6) * 1.0e8 + 0.5) / 1.0e8;

  # A model's cost block, in per-1M USD like every provider and models.dev
  # publishes. config.yaml stores per-token because LiteLLM wants it that way;
  # converting here rather than there keeps the spend-critical literals exact.
  costOf =
    info:
    lib.filterAttrs (_: v: v != null) {
      input = if info ? input_cost_per_token then perMillion info.input_cost_per_token else null;
      output = if info ? output_cost_per_token then perMillion info.output_cost_per_token else null;
      cache_read =
        if info ? cache_read_input_token_cost then perMillion info.cache_read_input_token_cost else null;
      cache_write =
        if info ? cache_creation_input_token_cost then
          perMillion info.cache_creation_input_token_cost
        else
          null;
    };

  entryOf =
    m:
    let
      info = m.model_info;
      meta = src.harness.${m.model_name};
      efforts = meta.efforts or null;
      notes = meta.notes or [ ];
      isChat = (info.mode or null) == "chat";
    in
    lib.filterAttrs (_: v: v != null) {
      id = m.model_name;
      # `mode` is LiteLLM's own notion; "responses" entries are the ChatGPT-Codex
      # models, which declare nothing else.
      mode = info.mode or null;

      limit =
        if isChat then
          {
            context = info.max_input_tokens;
            output = info.max_output_tokens;
          }
        else
          null;

      cost = if isChat then costOf info else null;

      tool_call = info.supports_function_calling or null;
      reasoning = info.supports_reasoning or null;
      structured_output = info.supports_response_schema or null;

      modalities =
        if isChat then
          {
            input = [ "text" ] ++ lib.optional (info.supports_vision or false) "image";
            output = [ "text" ];
          }
        else
          null;

      reasoning_options =
        if efforts == null then
          null
        else
          [
            {
              type = "effort";
              values = efforts;
            }
          ];

      notes = if notes == [ ] then null else notes;
    };

  manifest = {
    # What a harness needs to actually connect. The key is NOT included: every
    # client needs its own, and this file is public.
    base_url = "https://litellm.calvo.dev/v1";
    auth = "Bearer token in the Authorization header; ask the proxy owner for a key.";

    # Read this before trusting the capability flags below.
    caveats = [
      "Flags describe the ROUTE this proxy uses (openai/ + chat/completions), not the upstream model's full capability. Several models can do more on their native surface than is advertised here."
      "reasoning_options lists what the upstream accepts. LiteLLM forwards any value because every openai/-prefixed entry allowlists reasoning_effort, so an unsupported value fails at the provider rather than being rejected locally."
      "A model with no reasoning_options entry has an unverified ladder. Absence means unknown, not unsupported."
      "cost is per 1,000,000 tokens in USD and reflects what we believe the traffic is worth, which for the cc-* models is deliberately the undiscounted market rate rather than the invoice Command Code sends."
      "Do not read /v1/models for metadata: it returns names only, with a hardcoded created timestamp and owned_by 'openai' for every model regardless of provider."
      "A `hyper-*-dft` id is the same upstream model as its `hyper-*` primary, served on a second prepaid Hyper account. The pair is deliberately identical in limits, cost and capabilities. Prefer the primary: the proxy already falls back to the -dft twin automatically when the primary's balance is exhausted, so naming the twin directly gains nothing and gives up that failover. It is listed so the spillover capacity is visible rather than hidden."
    ];

    models = lib.listToAttrs (
      map (m: {
        name = m.model_name;
        value = entryOf m;
      }) src.modelList
    );
  };

in
# Fail the build rather than ship a manifest with an unreviewed model in it.
assert lib.assertMsg (undecided == [ ] && orphaned == [ ]) ''
  models.nix: harness metadata is out of sync with modelList.
    in modelList but missing from harness: ${lib.concatStringsSep ", " undecided}
    in harness but no such model:          ${lib.concatStringsSep ", " orphaned}
  Every model needs an explicit `efforts` decision (use null if genuinely unknown).
'';
manifest
