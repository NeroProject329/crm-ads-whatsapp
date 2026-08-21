import { forwardBackendRequest } from '@/lib/backend/forward';

type RouteContext = Readonly<{ params: Promise<Readonly<{ employeeId: string }>> }>;

export async function PATCH(request: Request, context: RouteContext): Promise<Response> {
  const { employeeId } = await context.params;
  return forwardBackendRequest(request, `/management/employees/${encodeURIComponent(employeeId)}`);
}
