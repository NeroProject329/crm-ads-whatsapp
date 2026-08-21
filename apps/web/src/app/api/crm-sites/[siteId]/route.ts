import { forwardBackendRequest } from '@/lib/backend/forward';

type RouteContext = Readonly<{ params: Promise<Readonly<{ siteId: string }>> }>;

export async function PATCH(request: Request, context: RouteContext): Promise<Response> {
  const { siteId } = await context.params;
  return forwardBackendRequest(request, `/sites/${encodeURIComponent(siteId)}`);
}
