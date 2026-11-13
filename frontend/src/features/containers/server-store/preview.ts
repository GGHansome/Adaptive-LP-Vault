import { useState } from 'react';
import { useQuery, type QueryKey } from '@tanstack/react-query';

// Results are keyed by identity and exact inputs. A late response can only update its own cache entry.
export function usePreviewQuery<T>(queryKey: QueryKey, ready: boolean, queryFn: () => Promise<T>) {
  const key = JSON.stringify(queryKey);
  const [request, setRequest] = useState<{ key: string; sequence: number }>();
  const enabled = ready && request?.key === key;
  const query = useQuery({
    queryKey: [...queryKey, request?.sequence],
    queryFn,
    enabled,
    retry: false,
    staleTime: Infinity,
    gcTime: 0,
    refetchOnWindowFocus: false,
  });
  return {
    data: enabled && !query.isError ? query.data : undefined,
    error: enabled ? query.error : null,
    loading: enabled && query.isFetching,
    request: () => {
      if (ready) setRequest((previous) => ({ key, sequence: (previous?.sequence ?? 0) + 1 }));
    },
    clear: () => setRequest(undefined),
  };
}
