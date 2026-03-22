export function LoadingSpinner({ size = 'md' }: { size?: 'sm' | 'md' | 'lg' }) {
  const px = { sm: 'w-4 h-4', md: 'w-8 h-8', lg: 'w-12 h-12' }[size];
  return (
    <div className={`${px} border-2 border-eve-panel-border border-t-eve-cyan rounded-full animate-spin`} />
  );
}
