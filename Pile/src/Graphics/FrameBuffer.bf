using System.Collections;
using System;

using internal Pile;

namespace Pile
{
	public class FrameBuffer : RenderTarget
	{
		internal abstract class Platform
		{
			internal readonly List<Texture> Attachments = new List<Texture>() ~ DeleteContainerAndItems!(_);
			internal abstract void Resize(int32 width, int32 height);
		}

		internal readonly Platform platform ~ delete _;

		public int AttachmentCount => platform.Attachments.Count;

		public override Point2 RenderSize => renderSize;
		Point2 renderSize;

		public this(int32 width, int32 height)
			: this(width, height, .Color) {}

		public this(int32 width, int32 height, params TextureFormat[] attachments)
		{
			Runtime.Assert(width > 0 || height > 0, "FrameBuffer size must be larger than 0");
			Runtime.Assert(attachments.Count > 0, "FrameBuffer needs at least one attachment");
			renderSize = Point2(width, height);
			
			platform = Core.Graphics.CreateFrameBuffer(width, height, attachments);
			Renderable = true;
		}

		public Texture this[int index]
		{
			get => platform.Attachments[index];
		}

		public Result<void> Resize(int32 width, int32 height)
		{
			if (width <= 0 || height <= 0)
				LogErrorReturn!("FrameBuffer size must be larger than 0");

			if (renderSize.X != width || renderSize.Y != height)
			{
				renderSize.X = width;
				renderSize.Y = height;

				platform.Resize(width, height);
			}
			return .Ok;
		}

		public static operator Texture(FrameBuffer target) => target.platform.Attachments[0];
	}
}
