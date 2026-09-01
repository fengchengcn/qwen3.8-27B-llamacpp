# vLLM endpoint plugin: 挂载 Anthropic Messages API (/v1/messages)
# vLLM 0.27.1 的 anthropic 路由存在但未内置注册, 通过 vllm.endpoint_plugins 入口点挂载
from fastapi import FastAPI

from vllm.entrypoints.anthropic.api_router import router as anthropic_router
from vllm.entrypoints.anthropic.serving import AnthropicServingMessages
from vllm.entrypoints.chat_utils import load_chat_template


class AnthropicPlugin:
    name = "anthropic"
    required_tasks = None

    def attach_router(self, app: FastAPI) -> None:
        app.include_router(anthropic_router)

    async def init_state(self, engine_client, state, args) -> None:
        state.anthropic_serving_messages = AnthropicServingMessages(
            engine_client=engine_client,
            models=state.openai_serving_models,
            response_role=args.response_role,
            online_renderer=state.online_renderer,
            request_logger=None,
            chat_template=load_chat_template(args.chat_template),
            chat_template_content_format=args.chat_template_content_format,
            reasoning_parser=args.structured_outputs_config.reasoning_parser,
            enable_auto_tools=args.enable_auto_tool_choice,
            tool_parser=args.tool_call_parser,
            default_chat_template_kwargs=args.default_chat_template_kwargs,
        )


def get_plugin():
    return AnthropicPlugin()
