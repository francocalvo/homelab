# The complete LiteLLM proxy config, as data. Rendered to YAML by
# ../container-litellm.nix and mounted into the container at /app/config.yaml.
#
# Kept separate from the container module so the same attrset can be imported by
# anything else that needs to know what this proxy serves — notably the planned
# public models.json manifest, which must not become a second hand-maintained
# copy of the model list.
{ lib }:

{
  model_list = (import ./models.nix { inherit lib; }).modelList;

  litellm_settings = {
    # /v1/messages for non-Anthropic models: bridge via chat/completions, not the
    # OpenAI Responses API.
    #
    # LiteLLM defaults to sending any openai/-prefix model on this endpoint to the
    # provider's /responses route (_RESPONSES_API_PROVIDERS in
    # llms/anthropic/experimental_pass_through/messages/handler.py). That broke
    # three separate ways here, all verified 2026-08-17:
    #   - 404 on providers that have no /responses route at all. Command Code
    #     answers "POST /provider/v1/responses is not a registered API route", so
    #     every cc-* model was simply unusable on /v1/messages.
    #   - malformed SSE: mimo-v2.5 streamed content_block_delta with index -1 and
    #     no content_block_start/content_block_stop events whatsoever.
    #   - spec violations on reasoning models: hyper-glm-5.2 and hyper-kimi-k3
    #     each emitted TWO message_start events and opened content block 1 before
    #     closing block 0. Strict Anthropic clients (Claude Code, the official
    #     SDK) reject both shapes.
    # It also threw a non-blocking AnthropicResponse validation traceback per
    # request in the logging worker; spend was still recorded correctly, so that
    # part was noise rather than data loss.
    #
    # Native anthropic/-prefix models never used this path and were always
    # well-formed — this setting does not affect them.
    use_chat_completions_url_for_anthropic_messages = true;
  };

  general_settings = {
    master_key = "os.environ/LITELLM_MASTER_KEY";
    database_url = "os.environ/DATABASE_URL";
    # Models can also be added at runtime via /model/new, which stores them in
    # Postgres. Prefer defining them in models.nix: a DB entry and a config entry
    # with the same model_name both register, giving a silent 2-deployment
    # round-robin.
    store_model_in_db = true;
  };
}
