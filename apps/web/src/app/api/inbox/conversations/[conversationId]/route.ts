import { forwardBackendRequest } from '@/lib/backend/forward';

type RouteContext = Readonly<{ params: Promise<Readonly<{ conversationId: string }>> }>;

export async function GET(request: Request, context: RouteContext): Promise<Response> {
  const { conversationId } = await context.params;
  return forwardBackendRequest(request, `/inbox/conversations/${encodeURIComponent(conversationId)}`);
}

export async function PATCH(request: Request, context: RouteContext): Promise<Response> {
  const { conversationId } = await context.params;
  return forwardBackendRequest(request, `/inbox/conversations/${encodeURIComponent(conversationId)}`);
}
