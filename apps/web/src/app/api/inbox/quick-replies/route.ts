import { forwardBackendRequest } from '@/lib/backend/forward';

export function GET(request: Request): Promise<Response> {
  return forwardBackendRequest(request, '/inbox/quick-replies');
}

export function POST(request: Request): Promise<Response> {
  return forwardBackendRequest(request, '/inbox/quick-replies');
}
