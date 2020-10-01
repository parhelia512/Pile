using System;
using SoLoud;

namespace Pile.Implementations
{
	public class SL_Audio : Audio
	{
		uint32 version;
		public override uint32 MajorVersion => version;

		public override uint32 MinorVersion => 0;

		String api = new String("SoLoud ") ~ delete _;
		public override String ApiName => api;

		Soloud* slPtr;

		public ~this()
		{
			SL_Soloud.Deinit(slPtr);
			SL_Soloud.Destroy(slPtr);
		}

		protected override Result<void, String> Initialize()
		{
			slPtr = SL_Soloud.Create();
			version = SL_Soloud.GetVersion(slPtr);
			SL_Soloud.GetBackendId(slPtr).ToString(api);

			// try to play sound manually here ..
			//SL_Openmpt.LoadMem()

			return .Ok;
		}

		public override void PlayInternal(AudioClip clip, float volume = 1, float pan = 0, bool paused = false, AudioBus bus = null)
		{

		}

		public override void StopInternal(params AudioInstance[] instances)
		{

		}
	}
}
