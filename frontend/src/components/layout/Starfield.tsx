import { useRef, useEffect } from 'react';

interface Star {
  x: number;
  y: number;
  z: number;
  r: number;
}

export function Starfield() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animId: number;
    let stars: Star[] = [];

    function resize() {
      canvas!.width = window.innerWidth;
      canvas!.height = window.innerHeight;
      const count = Math.max(140, Math.floor((canvas!.width * canvas!.height) / 10500));
      stars = Array.from({ length: count }, () => ({
        x: Math.random() * canvas!.width,
        y: Math.random() * canvas!.height,
        z: 0.5 + Math.random() * 1.4,
        r: Math.random() * 1.6,
      }));
    }

    function render() {
      ctx!.clearRect(0, 0, canvas!.width, canvas!.height);
      for (const star of stars) {
        const alpha = 0.16 + star.z * 0.3;
        ctx!.globalAlpha = alpha;
        ctx!.fillStyle = '#dce9ff';
        ctx!.beginPath();
        ctx!.arc(star.x, star.y, star.r, 0, Math.PI * 2);
        ctx!.fill();
        star.y += star.z * 0.15;
        if (star.y > canvas!.height) {
          star.y = 0;
          star.x = Math.random() * canvas!.width;
        }
      }
      animId = requestAnimationFrame(render);
    }

    resize();
    render();
    window.addEventListener('resize', resize);

    return () => {
      cancelAnimationFrame(animId);
      window.removeEventListener('resize', resize);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      className="fixed inset-0 pointer-events-none"
      style={{ zIndex: -1 }}
    />
  );
}
