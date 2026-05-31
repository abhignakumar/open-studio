import { Monitor, CircleX } from 'lucide-react';

export default function App() {
  function handleCloseCurrentWindow() {
    window.electronAPI.closeCurrentWindow();
  }

  async function handleListDisplaySources() {
    try {
      await window.electronAPI.listDisplaySources();
    } catch (error) {
      console.error('Failed to list display sources', error);
    }
  }

  return (
    <div
      className="h-screen flex bg-black p-2"
      style={{ WebkitAppRegion: 'drag' } as React.CSSProperties}
    >
      <div className="flex w-1/2 justify-center items-center pr-2 border-r border-[#3d3d3d]">
        <button
          className="flex flex-col justify-center items-center bg-[#2b2b2b] rounded-xl w-full h-full hover:bg-[#3d3d3d] transition-colors duration-300 ease-in-out"
          style={{ WebkitAppRegion: 'no-drag' } as React.CSSProperties}
          onClick={handleCloseCurrentWindow}
        >
          <CircleX color="white" />
        </button>
      </div>
      <div className="flex w-1/2 justify-center items-center pl-2">
        <button
          className="flex flex-col justify-center items-center bg-[#2b2b2b] rounded-xl w-full h-full hover:bg-[#3d3d3d] transition-colors duration-300 ease-in-out"
          style={{ WebkitAppRegion: 'no-drag' } as React.CSSProperties}
          onClick={handleListDisplaySources}
        >
          <Monitor color="white" className="mb-1" strokeWidth={3} size={18} />
          <div className="text-white select-none text-xs">Display</div>
        </button>
      </div>
    </div>
  );
}
