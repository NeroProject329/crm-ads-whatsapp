import { forwardBackendRequest } from '@/lib/backend/forward';

type RouteContext = Readonly<{ params: Promise<Readonly<{ quickReplyId: string }>> }>;

export async function PATCH(request: Request, context: RouteContext): Promise<Response> {
  const { quickReplyId } = await context.params;
  return forwardBackendRequest(request, `/inbox/quick-replies/${encodeURIComponent(quickReplyId)}`);
}

export async function DELETE(request: Request, context: RouteContext): Promise<Response> {
  const { quickReplyId } = await context.params;
  return forwardBackendRequest(request, `/inbox/quick-replies/${encodeURIComponent(quickReplyId)}`);
}
