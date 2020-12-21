using System;
using OpenGL43;

using internal Pile;

namespace Pile
{
	extension FrameBuffer
	{
		uint32 frameBufferID;

		protected internal override void Initialize(uint32 width, uint32 height, TextureFormat[] attachments)
		{
			Attachments.Count = attachments.Count;
			for (int i = 0; i < Attachments.Count; i++)
			{
				let attachment = new Texture(width, height, attachments[i]);
				attachment.isFrameBuffer = true;
				Attachments.Add(attachment);
			}
		}

		public ~this()
		{
			Delete();
		}

		protected internal override void ResizeAndClearInternal(uint32 width, uint32 height)
		{
			Delete();

			for (int i = 0; i < Attachments.Count; i++)
				Attachments[i].ResizeAndClear(width, height);
		}

		internal void Bind()
		{
			if (frameBufferID == 0)
			{
				GL.glGenFramebuffers(1, &frameBufferID);
				GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, frameBufferID);

				uint color = 0;
				for (let texture in Attachments)
				{
					if (texture.format.IsColorFormat())
					{
						GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_COLOR_ATTACHMENT0 + color, GL.GL_TEXTURE_2D, texture.textureID, 0);
						color++;
					}
					else
						GL.glFramebufferTexture2D(GL.GL_FRAMEBUFFER, GL.GL_DEPTH_STENCIL_ATTACHMENT, GL.GL_TEXTURE_2D, texture.textureID, 0);
				}
			}
			else
				GL.glBindFramebuffer(GL.GL_FRAMEBUFFER, frameBufferID);
		}

		void Delete()
		{
			if (frameBufferID > 0)
			{
				Core.Graphics.frameBuffersToDelete.Add(frameBufferID);
				frameBufferID = 0;
			}
		}
	}
}
