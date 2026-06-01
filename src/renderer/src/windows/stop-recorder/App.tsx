import { Square } from 'lucide-react';

import { stopRecorderApi } from './api';

export default function App() {
  function handleStopRecording() {
    stopRecorderApi.stopRecording();
  }

  return (
    <div
      className="h-screen flex bg-black p-2"
      style={{ WebkitAppRegion: 'drag' } as React.CSSProperties}
    >
      <div className="flex w-full justify-center items-center">
        <button
          className="flex flex-col justify-center items-center bg-[#2b2b2b] rounded-xl w-full h-full hover:bg-[#3d3d3d] transition-colors duration-300 ease-in-out"
          style={{ WebkitAppRegion: 'no-drag' } as React.CSSProperties}
          onClick={handleStopRecording}
        >
          <Square color="white" strokeWidth={3} />
        </button>
      </div>
    </div>
  );
}
