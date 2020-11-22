using System;

using internal Pile;

namespace Pile.Implementations
{
	class Null_MixingBus : MixingBus.Platform
	{
		internal bool masterBus;
		internal override bool IsMasterBus => masterBus;

		[SkipCall]
		internal override void Initialize(MixingBus bus) {}

		[SkipCall]
		internal override void SetVolume(float volume) {}

		[SkipCall]
		internal override void AddBus(MixingBus bus) {}

		[SkipCall]
		internal override void RemoveBus(MixingBus bus) {}

		[SkipCall]
		internal override void AddSource(AudioSource source) {}

		[SkipCall]
		internal override void RemoveSource(AudioSource source) {}

		[SkipCall]
		internal override void RedirectInputsToMaster() {}
	}
}
