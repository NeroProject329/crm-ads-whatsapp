import { forwardBackendRequest } from '@/lib/backend/forward';

export function GET(request: Request): Promise<Response> {
  return forwardBackendRequest(request, '/management/organization');
}

export function PATCH(request: Request): Promise<Response> {
  return forwardBackendRequest(request, '/management/organization');
}
