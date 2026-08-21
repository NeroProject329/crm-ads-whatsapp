import { authorizedBackendRequest } from '@/lib/auth/server';

export async function forwardBackendRequest(
  request: Request,
  backendPath: string,
): Promise<Response> {
  const headers = new Headers();
  const contentType = request.headers.get('content-type');

  if (contentType) {
    headers.set('Content-Type', contentType);
  }

  const method = request.method.toUpperCase();
  const body = method === 'GET' || method === 'HEAD' ? undefined : await request.arrayBuffer();
  const search = new URL(request.url).search;
  const response = await authorizedBackendRequest(`${backendPath}${search}`, {
    method,
    headers,
    ...(body !== undefined ? { body } : {}),
  });

  const responseHeaders = new Headers({ 'Cache-Control': 'no-store' });
  const responseContentType = response.headers.get('content-type');

  if (responseContentType) {
    responseHeaders.set('Content-Type', responseContentType);
  }

  return new Response(response.body, {
    status: response.status,
    headers: responseHeaders,
  });
}
