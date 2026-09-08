# LiteLLM model_list — the single source of truth for what this proxy serves.
#
# This was moved out of the `litellm_config` sops secret on 2026-08-19. It holds
# no credentials: every provider key is an `os.environ/NAME` pointer resolved at
# request time from `litellm_env`, which IS still encrypted. What lives here is
# model names, published prices, capability flags and four api_base hostnames.
#
# It is plain Nix rather than a YAML blob so that config.yaml and (next) the
# public models.json manifest generate from ONE definition and cannot drift.
# That drift is not hypothetical: on 2026-08-19 the two DeepSeek zen entries were
# found carrying prices that matched no tier the proxy actually bills against.
#
# Prices are per TOKEN, as LiteLLM wants them. Providers publish per 1M, so the
# comments quote per-1M and the literals are the divided value. The literals are
# written out rather than computed from a `perMillion` helper on purpose: float
# division can land a bit off the directly-parsed decimal, and these numbers feed
# spend reporting.
{ lib }:

let
  # Every openai/-prefix entry gets allowed_openai_params = ["reasoning_effort"].
  # LiteLLM decides which params a model accepts from its own model map. These
  # models are not in it, so it falls back to the base OpenAI param set, which has
  # no reasoning_effort, and rejects the request with a 400 before it ever reaches
  # the provider. The allowlist tells LiteLLM to pass it through.
  #
  # The 400 suggests `litellm_settings: drop_params: true` as the fix. Do NOT do
  # that: it silently discards the parameter instead, so requests stop failing
  # while the effort setting quietly stops working. Verified 2026-08-18 on hyper
  # deepseek-v4-flash-0731 that Hyper genuinely honours it — reasoning tokens ran
  # 0 at none/minimal, 924 at xhigh, 3571 at max.
  #
  # Upstream support is NOT uniform, and the allowlist does not change that:
  #   hyper        - full ladder none|minimal|low|medium|high|xhigh|max (per model)
  #   commandcode  - honours it but validates the value, accepting only
  #                  low|medium|high|xhigh|max; "none" returns a 400 from them
  #   zen / umans  - accept the param without error but never report reasoning
  #                  tokens in usage, so whether it does anything is unverified.
  #                  ONE exception: zen's glm-5.3-flash does report them, and
  #                  rejects any rung outside low|high|max with a 400 that names
  #                  the accepted set (verified 2026-08-28)
  #   muse         - minimal|low|medium|high|xhigh; no "none", no "max"
  #
  # `upstream` is always passed explicitly and never derived from the model_name:
  # they diverge on every provider except zen (hyper- prefixes are stripped, and
  # Command Code's slugs are vendor-qualified, e.g. cc-glm-5.2 -> zai-org/GLM-5.2).
  openaiCompat =
    { apiBase, apiKey }:
    name: upstream: info: {
      model_name = name;
      litellm_params = {
        model = "openai/${upstream}";
        api_base = apiBase;
        api_key = apiKey;
        allowed_openai_params = [ "reasoning_effort" ];
      };
      model_info = info;
    };

  zen = openaiCompat {
    apiBase = "https://opencode.ai/zen/go/v1";
    apiKey = "os.environ/OPENCODE_GO_API_KEY";
  };

  umans = openaiCompat {
    apiBase = "https://api.code.umans.ai/v1";
    apiKey = "os.environ/UMANS_API_KEY";
  };

  cc = openaiCompat {
    apiBase = "https://api.commandcode.ai/provider/v1";
    apiKey = "os.environ/COMMANDCODE_API_KEY";
  };

  # Bound rather than inlined because `isHyper` below picks the entries to mirror
  # by matching on it. See the -dft block immediately after.
  hyperApiBase = "https://hyper.charm.land/v1";

  hyper = openaiCompat {
    apiBase = hyperApiBase;
    apiKey = "os.environ/HYPER_API_KEY";
  };

  # ---- The second Hyper account, as derived `-dft` mirrors -----------------
  #
  # Hyper bills prepaid "hypercredits" per ACCOUNT, so a second account buys a
  # second balance, not extra rate limit. Every hyper entry therefore gets a
  # `<name>-dft` twin, identical but for the credential, and ./config.nix wires
  # <name> -> [<name>-dft] as a LiteLLM fallback: drain the primary, then spill.
  #
  # WHY SEPARATE MODEL GROUPS, rather than two deployments in one group with a
  # routing strategy across them — two independent reasons, both verified
  # against the router source in litellm 1.82.0 on 2026-09-04:
  #
  #   1. Cache locality. Hyper caches implicitly: there is a real cache_read
  #      rate but no cache_control in the openai/ request shape, so a prompt
  #      only hits warm cache if it lands on the SAME account that saw its
  #      prefix. One credential per group means the account is a property of the
  #      model name and never varies, so this holds by construction. The
  #      alternative is LiteLLM's `deployment_affinity` pre-call check, which
  #      pins per virtual-key hash on a TTL — strictly weaker, and pointless
  #      here. (Its sibling check `prompt_caching` is useless for Hyper at any
  #      rate: PromptCachingCache.extract_cacheable_prefix returns [] unless the
  #      request carries explicit cache_control blocks, so it silently no-ops on
  #      every openai/-prefixed entry in this file.)
  #
  #   2. Exhaustion actually fails over. router_utils/cooldown_handlers.py's
  #      _is_cooldown_required cools a deployment down for 4xx ONLY on 429, 401,
  #      408 and 404, and utils.py's _should_retry retries only on 408, 409, 429
  #      and 5xx. Both sets are hardcoded — cooldown_time tunes duration only,
  #      and allowed_fails_policy sits behind the same gate. So if Hyper answers
  #      an empty balance with 402 (the natural code for prepaid credit) or a
  #      plain 400, in-group failover does NOT happen: the error goes straight
  #      to the client and the dry deployment stays in the healthy pool.
  #      Cross-group `fallbacks` are dispatched from a blanket `except
  #      Exception` in Router.async_function_with_fallbacks with no status-code
  #      gate, so they fire on any error, 402 included.
  #
  # The known cost of (2): once the primary is dry, every request pays one failed
  # round-trip to it before spilling, forever, because nothing cools it down.
  # Watch `usage.remaining.hypercredits` (returned on every chat/completions
  # response) rather than waiting to discover this through latency.
  #
  # The mirrors are DERIVED, never written out: prices, limits, capability flags,
  # upstream id and reasoning ladder all come from the primary, so the two
  # accounts cannot drift. Adding a hyper model adds its twin and its fallback.
  dftSuffix = "-dft";

  isHyper = m: (m.litellm_params.api_base or null) == hyperApiBase;

  dftOf =
    m:
    m
    // {
      model_name = m.model_name + dftSuffix;
      litellm_params = m.litellm_params // {
        api_key = "os.environ/HYPER_DFT_API_KEY";
      };
    };

  # Native provider: no api_base, LiteLLM knows the route.
  anthropic =
    name: upstream: info: {
      model_name = name;
      litellm_params = {
        model = "anthropic/${upstream}";
        api_key = "os.environ/ANTHROPIC_API_KEY";
      };
      model_info = info;
    };

  # OAuth device-code flow, NOT an api_key — see the block comment further down.
  # These deliberately declare nothing but `mode`, because none of the usual
  # metadata is known for ChatGPT-authenticated Codex.
  chatgpt = name: upstream: {
    model_name = name;
    litellm_params.model = "chatgpt/${upstream}";
    model_info.mode = "responses";
  };

  # Shape for a chat model's model_info. Optional cost fields default to null and
  # are dropped, so an entry only declares what its provider actually publishes —
  # omission is meaningful here and must not become a zero.
  #
  # max_tokens is deliberately tied to maxOut: it is a legacy ALIAS for the output
  # cap, not the context window. Setting it to the context window is a real and
  # easy mistake, so the shape makes it unrepresentable.
  chatInfo =
    {
      maxIn,
      maxOut,
      inCost,
      outCost,
      cacheRead ? null,
      cacheWrite ? null,
      tools ? true,
      toolChoice ? true,
      reasoning,
      vision,
      schema,
    }:
    lib.filterAttrs (_: v: v != null) {
      mode = "chat";
      max_input_tokens = maxIn;
      max_output_tokens = maxOut;
      max_tokens = maxOut;
      input_cost_per_token = inCost;
      output_cost_per_token = outCost;
      cache_read_input_token_cost = cacheRead;
      cache_creation_input_token_cost = cacheWrite;
      supports_function_calling = tools;
      supports_tool_choice = toolChoice;
      supports_reasoning = reasoning;
      supports_vision = vision;
      supports_response_schema = schema;
    };

in
let
  # The hand-written entries. The exported `modelList` is this plus the derived
  # -dft mirrors — nothing outside this file should reference baseModelList.
  baseModelList = [
  # ---- opencode zen, GO plan: https://opencode.ai/zen/go/v1 ----------------
  # Pricing basis for this whole block is models.dev, opencode's own registry
  # (https://models.dev/api.json), provider key `opencode-go`. models.dev also
  # carries a separate `opencode` provider for zen proper, whose rates differ a
  # lot — read the GO column, not zen's. The zen API itself has no per-model info
  # route: GET /v1/models/<id> returns the website's HTML and /v1/models lists
  # only id/object/created/owned_by.
  (zen "glm-5.2" "glm-5.2" (chatInfo {
    maxIn = 1000000;
    maxOut = 131072;
    # $1.40 / $4.40 / $0.26 per 1M
    inCost = 0.0000014;
    outCost = 0.0000044;
    cacheRead = 0.00000026;
    reasoning = true;
    vision = false;
    schema = true;
  }))

  # Added 2026-08-28. Nearly 19x cheaper on input than glm-5.2 above and the only
  # zen entry here with working vision, so it is the default choice for anything
  # image-bearing on this proxy.
  #
  # Every flag below was smoke-tested on chat/completions (the route this proxy
  # uses), not taken from models.dev, because that is exactly where zen's shim has
  # lied before — see muse-spark further down:
  #   vision - REAL here. Sent a 320x240 photo as a base64 data URL and got back
  #            "A black Labrador puppy is sitting on a wooden floor", which is the
  #            picture. Same request shape returns an empty message on muse-spark.
  #   schema - response_format json_schema (strict) is accepted and ignored; the
  #            model answered in prose. models.dev claims structured_output true,
  #            and it may well be true on zen's /responses route, but not here.
  # Tool calling works (proper tool_calls with parsed arguments).
  #
  # models.dev names this model "GLM-5.3-Flash (2x usage)": requests count DOUBLE
  # against the GO plan's request allowance. Cheap per token, twice as expensive
  # per call against the quota.
  (zen "glm-5.3-flash" "glm-5.3-flash" (chatInfo {
    # models.dev limit.context. OpenRouter advertises 1310720 for the same model,
    # but zen's ceiling is what governs on this route.
    maxIn = 1000000;
    maxOut = 131072;
    # $0.075 / $0.25 / $0.015 per 1M. models.dev (opencode-go) and OpenRouter's
    # undiscounted z-ai/glm-5.3-flash rate agree to the digit, which is why the
    # cc- twin below carries identical numbers.
    inCost = 0.000000075;
    outCost = 0.00000025;
    cacheRead = 0.000000015;
    reasoning = true;
    vision = true;
    schema = false;
  }))

  # Corrected 2026-08-19. `pro` had been 0.435/0.87/0.003625, matching neither
  # the GO tier nor zen's, and `flash` carried zen's 0.14/0.28 with a cache_read
  # of 0.0028 that was 10x under zen's own 0.028 — apparently copied from
  # mimo-v2.5. Both only ever affected cost reporting, never routing.
  (zen "deepseek-v4-pro" "deepseek-v4-pro" (chatInfo {
    maxIn = 1000000;
    maxOut = 384000;
    # $0.66 / $1.98 / $0.022 per 1M
    inCost = 0.00000066;
    outCost = 0.00000198;
    cacheRead = 0.000000022;
    reasoning = true;
    vision = false;
    schema = true;
  }))

  (zen "deepseek-v4-flash" "deepseek-v4-flash" (chatInfo {
    maxIn = 1000000;
    maxOut = 384000;
    # $0.22 / $0.66 / $0.007 per 1M
    inCost = 0.00000022;
    outCost = 0.00000066;
    cacheRead = 0.000000007;
    reasoning = true;
    vision = false;
    schema = true;
  }))

  (zen "mimo-v2.5" "mimo-v2.5" (chatInfo {
    maxIn = 1000000;
    maxOut = 128000;
    # $0.14 / $0.28 / $0.0028 per 1M
    inCost = 0.00000014;
    outCost = 0.00000028;
    cacheRead = 0.0000000028;
    reasoning = true;
    vision = true;
    schema = false;
  }))

  # Muse Spark 1.2 (Meta), CONTRIBUTOR tier. Cheapest thing on this proxy at
  # $0.10/$0.20 per 1M and the highest GO allowance (45,300 req / 5h), because
  # opencode grants Meta permission to train on your prompts AND completions. It
  # is explicitly "Not ZDR" — do not route anything sensitive through this
  # model_name. The standard `muse-spark-1.2` (ZDR, $1.25/$4.25/$0.15) is a
  # separate upstream id and is deliberately NOT registered; add it as its own
  # entry if you want a non-training route to the same model.
  #
  # Do NOT probe the output cap against the endpoint — it does not enforce one.
  # Verified 2026-08-19 that /responses accepts max_output_tokens up to 1000000,
  # ~8x the real limit, and returns "completed". An earlier revision set 262144 on
  # the strength of that probe; models.dev gives limit.output = 131072.
  #
  # Budget output generously anyway: this is a reasoning model defaulting to
  # effort "high", and reasoning spends the same allowance as visible text. On
  # "say OK", max_tokens 64 came back as an EMPTY assistant message with all 64
  # tokens billed to reasoning (/responses confirms reasoning_tokens 61,
  # incomplete_details.reason "max_output_tokens"). ~200-900 completion tokens is
  # normal for a trivial prompt.
  #
  # The two false flags are properties of the ROUTE, not the model. models.dev
  # advertises attachment and structured_output, and both are true of Muse Spark,
  # but LiteLLM reaches it via openai/ + chat/completions and zen's shim drops
  # them there:
  #   vision - image parts work on /zen/go/v1/responses (correctly described a
  #            test photo) but over chat/completions the identical image returns
  #            an empty message with no usage, 3/3 attempts, while a text-only
  #            control on the same route succeeds. Verified 2026-08-19.
  #   schema - response_format json_schema (strict) is accepted and then ignored;
  #            the model replied with prose.
  # Tool calling IS real on chat/completions (proper tool_calls with parsed
  # arguments), hence tools/toolChoice stay true.
  (zen "muse-spark-1.2-contributor" "muse-spark-1.2-contributor" (chatInfo {
    maxIn = 1048576;
    maxOut = 131072;
    # $0.10 / $0.20 / $0.002 per 1M
    inCost = 0.0000001;
    outCost = 0.0000002;
    cacheRead = 0.000000002;
    reasoning = true;
    vision = false;
    schema = false;
  }))

  # ---- Umans Code: https://api.code.umans.ai/v1 ---------------------------
  # Key lives in litellm_env as UMANS_API_KEY.
  # Reasoning levels upstream: none | low (default) | high | max.
  # No cached-input price is published, so cacheRead is omitted and cache reads
  # bill at full input cost.
  (umans "umans-deepseek-v4-flash-0731" "umans-deepseek-v4-flash-0731" (chatInfo {
    maxIn = 1048576;
    maxOut = 393216;
    # $0.14 / $0.28 per 1M
    inCost = 0.00000014;
    outCost = 0.00000028;
    reasoning = true;
    vision = false;
    # UNVERIFIED: Umans does not advertise structured-output support; flip to true
    # if json_schema turns out to work.
    schema = false;
  }))

  # ---- OpenAI Codex via ChatGPT subscription ------------------------------
  # Auth is an OAuth device-code flow, NOT an api_key. The first request to one of
  # these blocks (up to 15 min) while LiteLLM prints a verification URL + code to
  # its logs and polls:
  #     journalctl -u podman-litellm -f
  # After the one-time login, tokens live in $CHATGPT_TOKEN_DIR/auth.json
  # (-> /mnt/arrakis/litellm/chatgpt-auth/) and refresh automatically. If the
  # refresh token is revoked the device flow restarts and requests hang until
  # someone completes the login again. Rate limits are the ChatGPT subscription's
  # own; treat as best-effort next to the API-key providers.
  #
  # Slugs verified 2026-08-10 against https://learn.chatgpt.com/docs/models.
  # LiteLLM's provider docs still advertise the gpt-5.3/5.4 generation; for
  # ChatGPT-authenticated Codex those are deprecated (gpt-5.3-codex already,
  # gpt-5.4 retires 2026-08-31), so they are deliberately not used here.
  # gpt-5.3-codex-spark is omitted: research preview, ChatGPT Pro only.
  (chatgpt "gpt-5.6-sol" "gpt-5.6-sol")
  (chatgpt "gpt-5.6-terra" "gpt-5.6-terra")
  (chatgpt "gpt-5.6-luna" "gpt-5.6-luna")

  # ---- Anthropic direct (key in litellm_env as ANTHROPIC_API_KEY) ---------
  # The fable tier is the highest-capability tier, above claude-opus-5 at 2x the
  # price. Both fable entries verified live against GET /v1/models: 1M context,
  # 128000 output, vision + structured outputs, adaptive thinking.
  #
  # THE REST OF THIS COMMENT APPLIES TO BOTH FABLE ENTRIES.
  #
  # Thinking is ALWAYS ON and is not configurable: an explicit
  # thinking={"type":"disabled"} returns 400 (the /models capability tree reports
  # thinking.types.disabled as null), and budget_tokens was removed across the
  # 5-series. Depth is controlled with output_config.effort (low..max) instead.
  # Nothing here sends a thinking block, so the default applies — but a client
  # that passes one through LiteLLM will 400 on these and not on the others.
  #
  # Requires 30-day data retention; orgs under zero data retention get a 400 on
  # EVERY request regardless of payload. Confirmed working on the current key.
  #
  # Like claude-opus-5, safety classifiers can return stop_reason "refusal" as a
  # normal HTTP 200 with empty content — a client that reads content[0] without
  # checking stop_reason sees an empty response rather than an error.

  # Added 2026-09-03. NOTE THE UPSTREAM ID: `claude-fable-5-1`, not
  # `claude-fable-5.1` — Anthropic spells the minor version with a hyphen, so this
  # is the one anthropic/ entry where model_name and upstream both need the odd
  # form. Verified 2026-09-03 against GET /v1/models/claude-fable-5-1 and a live
  # chat completion on the current key (no ZDR problem).
  #
  # THE CACHE READ RATE IS THE ONLY PRICE THAT MOVED vs claude-fable-5, and it
  # moved DOWN 4x. Base input/output are unchanged at $10/$50 and the 5-minute
  # cache write is unchanged at $12.50/1M, but cache hits bill at 0.025x input
  # instead of the 0.1x that every other model on this proxy uses: $0.25/1M
  # against fable 5's $1.00/1M. Do NOT "correct" this to 0.1x to match its
  # sibling — Anthropic documents 0.025x as specific to Fable 5.1 and Mythos 5.1.
  (anthropic "claude-fable-5-1" "claude-fable-5-1" (chatInfo {
    maxIn = 1000000;
    maxOut = 128000;
    # $10 / $50 per 1M, identical to fable 5. Cache reads $0.25 per 1M — 0.025x
    # input, NOT the usual 0.1x. 5-minute cache writes $12.50 per 1M (1.25x).
    inCost = 0.00001;
    outCost = 0.00005;
    cacheRead = 0.00000025;
    cacheWrite = 0.0000125;
    reasoning = true;
    vision = true;
    schema = true;
  }))

  (anthropic "claude-fable-5" "claude-fable-5" (chatInfo {
    maxIn = 1000000;
    maxOut = 128000;
    # $10 / $50 per 1M. Anthropic standard cache rates: reads 0.1x input,
    # 5-minute writes 1.25x.
    inCost = 0.00001;
    outCost = 0.00005;
    cacheRead = 0.000001;
    cacheWrite = 0.0000125;
    reasoning = true;
    vision = true;
    schema = true;
  }))

  (anthropic "claude-opus-5" "claude-opus-5" (chatInfo {
    maxIn = 1000000;
    maxOut = 128000;
    # $5 / $25 per 1M
    inCost = 0.000005;
    outCost = 0.000025;
    reasoning = true;
    vision = true;
    schema = true;
  }))

  (anthropic "claude-sonnet-5" "claude-sonnet-5" (chatInfo {
    maxIn = 1000000;
    maxOut = 128000;
    # Standard rates, $3 / $15 per 1M. Introductory pricing ($2/$10 per 1M) runs
    # through 2026-08-31, so spend over-reports slightly until then.
    inCost = 0.000003;
    outCost = 0.000015;
    reasoning = true;
    vision = true;
    schema = true;
  }))

  (anthropic "claude-haiku-4-5" "claude-haiku-4-5" (chatInfo {
    maxIn = 200000;
    maxOut = 64000;
    # $1 / $5 per 1M
    inCost = 0.000001;
    outCost = 0.000005;
    reasoning = true;
    vision = true;
    schema = true;
  }))

  # ---- Command Code: https://api.commandcode.ai/provider/v1 ---------------
  # Key lives in litellm_env as COMMANDCODE_API_KEY (Authorization: Bearer).
  # LiteLLM has no native `commandcode` provider (BerriAI/litellm#27582 is still
  # open), so these go through the openai/ prefix + api_base, like zen/umans.
  #
  # Slugs verified 2026-08-14 against GET /provider/v1/models, and every entry was
  # smoke-tested with a live request on the surface it declares. Names are `cc-`
  # prefixed so they don't collide (and silently load-balance) with the same
  # upstream models already exposed via zen.
  #
  # PRICING BASIS — deliberately NOT what Command Code bills. All cost fields come
  # from OpenRouter's public model list (https://openrouter.ai/api/v1/models,
  # snapshotted 2026-08-14), because:
  #   1. Command Code publishes no cache-WRITE rate at all, so cache writes would
  #      otherwise bill at full input cost. OpenRouter publishes it where the
  #      upstream provider charges one (here: gemini, the only one left).
  #   2. Command Code's advertised rates bake in promos ("75% off", "99% off",
  #      "free while capacity lasts"), which hides what the traffic is really
  #      worth. Its discount percentages are also relative to baselines that do
  #      not survive checking — the "99% off" MiMo V2.5 Pro price is identical to
  #      OpenRouter's undiscounted rate.
  # Consequence, by choice: LiteLLM spend reports the real market cost of this
  # traffic, NOT the invoice Command Code will send. Actual billing is lower
  # wherever a promo applies. Per-model comments record Command Code's own number
  # whenever it differs from the OpenRouter rate used here.
  #
  # maxIn comes from Command Code's /models context_length (their ceiling governs,
  # and it is sometimes lower than the model's true context). maxOut comes from
  # OpenRouter's top_provider.max_completion_tokens where published, else carried
  # over from this file's existing entry for the same upstream model, else marked
  # UNVERIFIED.
  (cc "cc-glm-5.2" "zai-org/GLM-5.2" (chatInfo {
    maxIn = 1000000;
    maxOut = 131072;
    # Command Code advertises $1.40/$4.40/$0.26 per 1M.
    inCost = 0.00000119;
    outCost = 0.00000374;
    cacheRead = 0.000000221;
    reasoning = true;
    vision = false;
    schema = true;
  }))

  # Added 2026-08-28, same upstream model as `glm-5.3-flash` (zen) above.
  #
  # NOTE THE SLUG. Command Code's GLM entries are `zai-org/GLM-<v>` (capitalised,
  # zai-org), but this one is `z-ai/glm-5.3-flash` — lowercase, different vendor
  # segment, matching OpenRouter's id rather than its own siblings. Verified
  # 2026-08-28 against GET /provider/v1/models; do not "fix" it to zai-org/GLM-5.3-Flash.
  #
  # Flags smoke-tested on this route 2026-08-28, same probes as the zen twin:
  # vision correctly described the test photo; tool calling returned proper
  # tool_calls. schema is false for a different reason than zen's — Command Code
  # returns valid JSON but ignores the supplied json_schema, answering with an
  # invented {"answer": "..."} envelope. That is worse than zen's prose: a client
  # doing json.loads() succeeds and then finds none of its fields.
  (cc "cc-glm-5.3-flash" "z-ai/glm-5.3-flash" (chatInfo {
    # Command Code's own context_length, which is higher than zen's ceiling for
    # the same model.
    maxIn = 1048576;
    # OpenRouter top_provider.max_completion_tokens.
    maxOut = 131072;
    # $0.075 / $0.25 / $0.015 per 1M, OpenRouter's undiscounted rate as per the
    # block header. Identical to models.dev's opencode-go figure, so unlike most
    # of this block there is no gap between what we report and the market rate.
    inCost = 0.000000075;
    outCost = 0.00000025;
    cacheRead = 0.000000015;
    reasoning = true;
    vision = true;
    schema = false;
  }))

  (cc "cc-deepseek-v4-pro" "deepseek/deepseek-v4-pro" (chatInfo {
    maxIn = 1000000;
    maxOut = 384000;
    # Undiscounted rate. Command Code bills a permanent 75% off
    # ($0.435/$0.87/$0.003625 per 1M), so its invoice runs well under what LiteLLM
    # reports here — the biggest gap of any model in this block.
    inCost = 0.000001168;
    outCost = 0.000002336;
    cacheRead = 0.00000009855;
    reasoning = true;
    vision = false;
    schema = true;
  }))

  (cc "cc-deepseek-v4-flash" "deepseek/deepseek-v4-flash" (chatInfo {
    maxIn = 1000000;
    maxOut = 384000;
    # Input/output match Command Code's own table. Cache reads do not: Command
    # Code advertises $0.0028 per 1M, OpenRouter $0.028 — a 10x spread. Using the
    # higher (undiscounted) figure.
    inCost = 0.00000014;
    outCost = 0.00000028;
    cacheRead = 0.000000028;
    reasoning = true;
    vision = false;
    schema = true;
  }))

  (cc "cc-gemini-3.7-flash" "google/gemini-3.7-flash" (chatInfo {
    maxIn = 1048576;
    # Confirmed by OpenRouter's top_provider.max_completion_tokens.
    maxOut = 65536;
    # The one model where the two sources disagree in the awkward direction:
    # OpenRouter's undiscounted rate ($0.375/$1.875) is LOWER than Command Code's
    # own claimed list price ($1.50/$7.50, currently 50% off to 2026-12-31 ->
    # $0.75/$3.75). OpenRouter wins for consistency with the rest of this block,
    # so if that promo lapses this entry under-reports 4x.
    inCost = 0.000000375;
    outCost = 0.000001875;
    cacheRead = 0.0000000375;
    # OpenRouter reports this as input_cache_write, but $0.0208/1M looks like
    # Gemini's per-hour cache STORAGE fee rather than a per-token write charge.
    # Treat this one number as shaky.
    cacheWrite = 0.0000000208333;
    reasoning = true;
    vision = true;
    schema = true;
  }))

  # Command Code lists Grok 4.6 as GOAT-plan-and-above; verified working on the
  # current key 2026-08-14, so treat a later 403 here as a plan change.
  (cc "cc-grok-4.6" "xai/grok-4.6" (chatInfo {
    maxIn = 500000;
    # UNVERIFIED: no published output cap on the Command Code side.
    maxOut = 131072;
    # OpenRouter and Command Code agree: $2/$6/$0.50 per 1M.
    inCost = 0.000002;
    outCost = 0.000006;
    cacheRead = 0.0000005;
    reasoning = true;
    vision = true;
    schema = true;
  }))

  # Free on Command Code while capacity lasts — the `-free` suffix is part of the
  # upstream slug, not a variant we picked. Priced here at OpenRouter's paid rate
  # for poolside/laguna-s-2.1 so the traffic shows its real worth instead of
  # vanishing from spend reports; the actual invoice for it is $0.
  (cc "cc-laguna-s-2.1" "poolside/laguna-s-2.1-free" (chatInfo {
    maxIn = 256000;
    # 32768 is measured, not documented, and is the one cap in this block that
    # bites: 49152+ is rejected with
    #   max_tokens (N): Input should be less than or equal to 32768
    # Do NOT raise this to OpenRouter's 131072 (that describes the paid
    # poolside/laguna-s-2.1, a different deployment from the `-free` variant
    # Command Code serves), and do not trust the gateway's own error at
    # max_tokens=999999, which claims a 262144 ceiling the backend won't honour.
    maxOut = 32768;
    inCost = 0.00000009;
    outCost = 0.00000018;
    cacheRead = 0.000000009;
    # UNVERIFIED: capability flags below are guesses for this model.
    reasoning = false;
    vision = false;
    schema = false;
  }))

  # ---- Hyper: https://hyper.charm.land/v1 (Charm) -------------------------
  # Key lives in litellm_env as HYPER_API_KEY (Authorization: Bearer). No native
  # `hyper` provider in LiteLLM, so these ride the openai/ prefix + api_base.
  #
  # Hyper serves three surfaces on the same key, all verified 2026-08-17:
  #   /v1/chat/completions  -> the entries below (openai/ prefix)
  #   /v1/messages          -> Anthropic-native, incl. tool_use blocks. No entry
  #                            below uses it (the `-anthropic` twins were pruned);
  #                            to add one back, use the anthropic/ prefix with
  #                            api_base ending in /messages.
  #   /v1/responses         -> OpenAI Responses API, works for every model.
  #                            Nothing extra to declare: LiteLLM's own
  #                            /v1/responses bridges onto these entries.
  #
  # Billing is prepaid "hypercredits" (1 credit = $0.05); every chat/completions
  # response carries usage.cost.usd and usage.remaining.hypercredits, so the
  # account balance is visible upstream and NOT in LiteLLM's spend tables.
  #
  # PRICING: taken verbatim from GET /v1/models (snapshotted 2026-08-17), which
  # publishes input/output/cache_create/cache_hit per 1M tokens. Two caveats:
  #   1. Where a cache field is 0 it is omitted rather than declared free. Hyper
  #      prices some models with cache_create = 0.5x input and cache_hit = 0;
  #      after pruning, hyper-llama-4-maverick was the only one of those and is
  #      now gone. Verified 2026-08-17 against two models of that family by
  #      sending an identical 13k-token prompt twice: both passes billed full
  #      input price and no cached_tokens field came back at all. They simply do
  #      not cache, so there is no discount being dropped and no write surcharge
  #      to declare. Models with a nonzero cache_hit do cache (kimi-k3 returns
  #      cached_tokens on a repeat) and carry the published read rate.
  #   2. maxOut is Hyper's declared per-model ceiling, which for most models is
  #      exactly 10% of context and is often far below what the model can actually
  #      emit (hyper-glm-5.2 caps at 32768 where zen serves the same model at
  #      131072). Their cap governs, so it is copied as-is — do not raise it to
  #      the upstream model's real limit.
  #
  # schema is false on EVERY entry, verified by smoke test: Hyper accepts
  # response_format json_schema and then silently ignores it, returning prose.
  # Requests do not fail, so a client that assumes structured output gets
  # malformed data rather than an error.
  #
  # reasoning follows observed reasoning_tokens in usage, not the /models
  # `reasoning` block — the two disagree in both directions.
  #
  # Tool calling was smoke-tested on all 26 models Hyper served on 2026-08-17 and
  # worked on every one. Note that reasoning is billed and counted before the tool
  # call, so a small max_tokens can swallow the whole budget and return prose
  # instead of a tool_call — some models needed ~1000 tokens of headroom.

  # Newer snapshot than the pro entry below and cheaper: also the only model here
  # with the full none|minimal|low|medium|high|xhigh|max reasoning_effort ladder.
  (hyper "hyper-deepseek-v4-flash-0731" "deepseek-v4-flash-0731" (chatInfo {
    maxIn = 1048576;
    maxOut = 384000;
    inCost = 0.00000013;
    outCost = 0.00000026;
    cacheRead = 0.000000028;
    reasoning = true;
    vision = false;
    schema = false;
  }))

  (hyper "hyper-deepseek-v4-pro-0813" "deepseek-v4-pro-0813" (chatInfo {
    maxIn = 1048576;
    maxOut = 262144;
    inCost = 0.000001437216;
    outCost = 0.000004311648;
    cacheRead = 0.0000000479072;
    reasoning = true;
    vision = false;
    schema = false;
  }))

  # Same upstream model as `glm-5.2` (zen) and `cc-glm-5.2` (Command Code). Hyper
  # is the most expensive of the three on input and caps output at 32768 against
  # their 131072.
  (hyper "hyper-glm-5.2" "glm-5.2" (chatInfo {
    maxIn = 1000000;
    maxOut = 32768;
    inCost = 0.0000014;
    outCost = 0.0000044;
    cacheRead = 0.00000028;
    reasoning = true;
    vision = false;
    schema = false;
  }))

  # Added 2026-09-03. Third route to the same upstream model as `glm-5.3-flash`
  # (zen) and `cc-glm-5.3-flash` (Command Code), and BY FAR the most expensive of
  # the three: $0.16332/$0.5444 against the other two's $0.075/$0.25, so ~2.2x on
  # input and output both. It buys nothing on limits — same 131072 output cap as
  # the zen twin. Reach for this one only when the GO plan's request allowance is
  # the binding constraint (zen bills this model DOUBLE against that allowance)
  # or when zen/Command Code are down.
  #
  # Unusual for this block in one good way: hyper caps most models' output at 10%
  # of context, but serves this one at the full 131072 rather than 104857.
  #
  # Flags smoke-tested on chat/completions 2026-09-03, not taken from /v1/models:
  #   vision    - REAL. Sent a 1400px UI screenshot as a base64 data URL and got
  #               back an accurate description of the layout and form fields.
  #   reasoning - REAL, and unlike zen/umans this route DOES report
  #               reasoning_tokens in usage.
  #   schema    - response_format json_schema (strict) is accepted and ignored;
  #               the model answered in prose, same as every other hyper entry.
  # Tool calling returns proper tool_calls with parsed arguments.
  (hyper "hyper-glm-5.3-flash" "glm-5.3-flash" (chatInfo {
    maxIn = 1048576;
    maxOut = 131072;
    # Hyper's published per-1M rates: $0.16332 / $0.5444 / cache_hit $0.0315752.
    # cache_create is published as 0, so cacheWrite is omitted rather than
    # declared free (see the block header) — this model does return cached_tokens
    # on a repeat, so the read rate is real and is carried.
    inCost = 0.00000016332;
    outCost = 0.0000005444;
    cacheRead = 0.0000000315752;
    reasoning = true;
    vision = true;
    schema = false;
  }))

  # Priced identically to Command Code's kimi-k3 ($3/$15/$0.30 per 1M) but with a
  # 131072 output cap that Command Code does not publish.
  (hyper "hyper-kimi-k3" "kimi-k3" (chatInfo {
    maxIn = 1048576;
    maxOut = 131072;
    inCost = 0.000003;
    outCost = 0.000015;
    cacheRead = 0.0000003;
    reasoning = true;
    vision = true;
    schema = false;
  }))
  ];

  # Harness-facing metadata that LiteLLM has no field for, keyed by model_name.
  #
  # This exists because /model_group/info structurally cannot express it: that
  # endpoint computes supported_openai_params from LiteLLM's own model map, which
  # does not know about our allowed_openai_params allowlist, so it reports
  # reasoning_effort as UNSUPPORTED on all 16 openai/-prefixed models here —
  # exactly inverted. An agent auto-configuring from the live endpoint would
  # disable reasoning across the fleet. Hence the generated manifest.
  #
  # `efforts` is the reasoning_effort ladder the UPSTREAM actually accepts. null
  # means genuinely unknown — the manifest omits the field rather than guessing,
  # because a wrong ladder is worse than an absent one. Note that LiteLLM will
  # forward any value (the allowlist sees to that), so an unsupported effort fails
  # at the provider, not here.
  #
  # ./manifest.nix asserts these keys exactly match modelList, so a model added
  # above without a decision here is a build error, not a silent gap. The -dft
  # mirrors are exempt only because they inherit their primary's entry below.
  baseHarness = {
    # zen accepts reasoning_effort without error but never reports reasoning
    # tokens in usage, so the ladder is unverifiable from outside. Not guessed.
    "glm-5.2".efforts = null;

    # The exception: this one DOES report reasoning tokens, and names its own
    # ladder in the rejection. medium/xhigh/none/minimal all 400 with
    # "[1210] This model always engages in thinking and cannot be disabled;
    # please use low, high, or max" — note that low still ran 7 reasoning tokens,
    # so "low" is the floor, not an off switch.
    "glm-5.3-flash" = {
      efforts = [ "low" "high" "max" ];
      notes = [
        "Counts DOUBLE against the opencode GO request allowance (models.dev names it \"GLM-5.3-Flash (2x usage)\"), despite being the cheapest per-token model on this proxy after muse-spark."
        "Rejects medium and xhigh with a 400 — unlike every other zen model here, which swallows any effort value. Send only low, high or max."
        "Vision works on chat/completions (verified with a photo), but json_schema is accepted and ignored, so structured output silently returns prose."
      ];
    };

    "deepseek-v4-pro".efforts = null;
    "deepseek-v4-flash".efforts = null;
    "mimo-v2.5".efforts = null;

    "muse-spark-1.2-contributor" = {
      # models.dev reasoning_options for this model. No "none", no "max".
      efforts = [ "minimal" "low" "medium" "high" "xhigh" ];
      notes = [
        "Defaults to effort high; reasoning spends the same budget as visible text. Allow >=1000 output tokens or trivial prompts return an empty message."
        "Not ZDR: opencode grants Meta permission to train on prompts and completions in exchange for the discounted contributor rate. Do not send sensitive input."
        "Vision and structured output work on /zen/go/v1/responses but are silently dropped on chat/completions, which is the route this proxy uses."
      ];
    };

    # Umans documents none | low (default) | high | max.
    "umans-deepseek-v4-flash-0731" = {
      efforts = [ "none" "low" "high" "max" ];
      notes = [ "No cached-input price published upstream, so cache reads bill at full input cost." ];
    };

    # ChatGPT-authenticated Codex. Depth is not exposed as reasoning_effort here.
    "gpt-5.6-sol".efforts = null;
    "gpt-5.6-terra".efforts = null;
    "gpt-5.6-luna".efforts = null;

    # Anthropic 5-series: depth via output_config.effort, low..max. Thinking is
    # always on and cannot be disabled, so there is no "none" rung.
    #
    # Ladder read straight off the capability tree in GET /v1/models/claude-fable-5-1
    # on 2026-09-03, which reports all five rungs supported including xhigh.
    "claude-fable-5-1" = {
      efforts = [ "low" "medium" "high" "xhigh" "max" ];
      notes = [
        "Thinking is always on: an explicit thinking={\"type\":\"disabled\"} returns 400 on this model and not on the others."
        "Requires 30-day data retention; zero-data-retention orgs get a 400 on every request."
        "Cache reads bill at 0.025x input ($0.25/1M), not the 0.1x every other model here uses — prompt caching is 4x cheaper on this model than on claude-fable-5, at identical base rates."
      ];
    };
    "claude-fable-5" = {
      efforts = [ "low" "medium" "high" "max" ];
      notes = [
        "Thinking is always on: an explicit thinking={\"type\":\"disabled\"} returns 400 on this model and not on the others."
        "Requires 30-day data retention; zero-data-retention orgs get a 400 on every request."
      ];
    };
    "claude-opus-5".efforts = [ "low" "medium" "high" "max" ];
    "claude-sonnet-5".efforts = [ "low" "medium" "high" "max" ];
    "claude-haiku-4-5".efforts = [ "low" "medium" "high" "max" ];

    # Command Code validates the value and rejects "none" with a 400.
    "cc-glm-5.2".efforts = [ "low" "medium" "high" "xhigh" "max" ];

    # Command Code's gateway validates against its own ladder before the request
    # reaches Z.ai, so medium and xhigh are accepted here even though the same
    # model rejects them via zen. Reasoning tokens confirm they do something
    # (0 at low, 468 at max on an identical prompt), but the middle rungs did not
    # come out monotonic in one sample — do not read the ladder as a dial.
    "cc-glm-5.3-flash" = {
      efforts = [ "low" "medium" "high" "xhigh" "max" ];
      notes = [
        "json_schema is ignored, but unlike most models here the reply is still valid JSON — an invented {\"answer\": \"...\"} envelope. A client that only checks json.loads() will not notice its schema was dropped."
        "Upstream slug is z-ai/glm-5.3-flash, not zai-org/GLM-5.3-Flash like the other Command Code GLM entries."
      ];
    };
    "cc-deepseek-v4-pro".efforts = [ "low" "medium" "high" "xhigh" "max" ];
    "cc-deepseek-v4-flash".efforts = [ "low" "medium" "high" "xhigh" "max" ];
    "cc-gemini-3.7-flash".efforts = [ "low" "medium" "high" "xhigh" "max" ];
    "cc-grok-4.6".efforts = [ "low" "medium" "high" "xhigh" "max" ];
    "cc-laguna-s-2.1" = {
      efforts = null;
      notes = [ "Capability flags are unverified guesses for this model. Output caps at 32768, measured not documented." ];
    };

    # Only hyper-deepseek-v4-flash-0731 was verified to take the full ladder
    # (reasoning tokens 0 at none/minimal, 924 at xhigh, 3571 at max on
    # 2026-08-18). The other three are per-model upstream and were not measured.
    "hyper-deepseek-v4-flash-0731".efforts = [ "none" "minimal" "low" "medium" "high" "xhigh" "max" ];
    "hyper-deepseek-v4-pro-0813".efforts = null;
    "hyper-glm-5.2" = {
      efforts = null;
      notes = [ "Hyper caps output at 32768 where zen serves the same model at 131072." ];
    };

    # Measured 2026-09-03. Every rung is ACCEPTED — no 400 on any of the seven,
    # unlike the zen twin, which rejects everything outside low|high|max. But
    # accepted is not the same as honoured: on an identical prompt, none, minimal,
    # medium and high all produced exactly 24 reasoning tokens (the default),
    # while low gave 15, max 42 and xhigh 63. So only low/xhigh/max visibly move
    # the dial, xhigh came out ABOVE max, and "none" does not disable reasoning.
    # The full ladder is listed because that is what upstream accepts; the notes
    # carry the caveat rather than pruning rungs that do not error.
    "hyper-glm-5.3-flash" = {
      efforts = [ "none" "minimal" "low" "medium" "high" "xhigh" "max" ];
      notes = [
        "Accepts all seven rungs without error, but only low, xhigh and max measurably changed reasoning-token spend in one sample; none/minimal/medium/high all landed on the default. \"none\" does NOT disable reasoning, and xhigh scored above max — do not read the ladder as a dial."
        "Same upstream model as zen's glm-5.3-flash and cc-glm-5.3-flash, but ~2.2x their price on both input and output for the same 131072 output cap. Prefer the zen or cc route unless the GO request allowance is the binding constraint."
        "Unlike zen and umans, this route does report reasoning_tokens in usage."
        "json_schema is accepted and silently ignored, returning prose — the standard hyper caveat."
      ];
    };
    "hyper-kimi-k3".efforts = null;
  };

  # Every hyper entry, in definition order. Single source for the -dft mirrors,
  # their harness entries and the fallback pairs, so all three stay in lockstep.
  hyperModels = lib.filter isHyper baseModelList;

  dftNameOf = m: m.model_name + dftSuffix;

in
{
  # LiteLLM's model_list, verbatim. Consumed by ./config.nix.
  modelList = baseModelList ++ map dftOf hyperModels;

  # A -dft twin serves the same upstream model over the same route as its
  # primary, so it inherits the primary's decision rather than carrying one of
  # its own — there is nothing about it that could differ. Deriving this is also
  # what keeps manifest.nix's modelList/harness assertion satisfiable without a
  # parallel set of hand-written entries to forget to update.
  harness = baseHarness // lib.listToAttrs (
    map (m: {
      name = dftNameOf m;
      value = baseHarness.${m.model_name};
    }) hyperModels
  );

  # LiteLLM `fallbacks` shape: a list of single-key { group = [ targets ]; }
  # attrsets. Consumed by ./config.nix as router_settings.fallbacks.
  hyperFallbacks = map (m: { ${m.model_name} = [ (dftNameOf m) ]; }) hyperModels;
}
