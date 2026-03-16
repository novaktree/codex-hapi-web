import { useEffect, useRef, useState } from 'react';
import { MOBILE_BREAKPOINT } from './lib/format';

export function useIsMobile() {
  const [isMobile, setIsMobile] = useState(() => window.innerWidth < MOBILE_BREAKPOINT);

  useEffect(() => {
    const onResize = () => setIsMobile(window.innerWidth < MOBILE_BREAKPOINT);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  return isMobile;
}

export function usePolling(callback, delay) {
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  useEffect(() => {
    if (!delay) return undefined;
    const timer = window.setInterval(() => {
      callbackRef.current();
    }, delay);
    return () => window.clearInterval(timer);
  }, [delay]);
}

