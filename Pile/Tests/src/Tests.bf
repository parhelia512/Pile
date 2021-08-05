using System;
using Pile;
using System.IO;
using System.Diagnostics;

namespace Test
{
	class Tests
	{
		[Test]
		static void TestCircularBuffer()
		{
			CircularBuffer<int> ints = scope .(5) { 1, 2, 3 };
			Test.Assert(ints.Capacity == 5);
			Test.Assert(ints.Count == 3);

			let set3 = (ints[0], ints[1], ints[2]);
			Test.Assert(set3 == (1, 2, 3));

			int i = 1;
			for (let val in ints)
			{
				Test.Assert(val == i);
				i++;
			}

			var num = ref ints.AddByRef();
			Test.Assert(num == default);
			num = 4;
			Test.Assert(ints[3] == 4);
			Test.Assert(ints.Front == 1);
			Test.Assert(ints.Back == 4);

			ints.Add(5);
			ints.Add(6);
			Test.Assert(ints.Count == 5);
			Test.Assert(ints.Front == 2);
			Test.Assert(ints.[Friend]mItems[1] == 2);
			Test.Assert(ints.Back == 6);
			Test.Assert(ints[4] == 6);
			Test.Assert(ints.[Friend]mItems[0] == 6);

			i = 2;
			for (let val in ints)
			{
				Test.Assert(val == i);
				i++;
			}

			i = 6;
			for (let val in ints.GetBackwardsEnumerator())
			{
				Test.Assert(val == i);
				i--;
			}

			ints.Resize(8);
			let set5 = (ints[0], ints[1], ints[2], ints[3], ints[4]);
			Test.Assert(set5 == (2, 3, 4, 5, 6));
			Test.Assert(ints.[Friend]mItems[0] == 2);
			Test.Assert(ints.Capacity == 8);
			Test.Assert(ints.Count == 5);

			ints.Clear();
			Test.Assert(ints.Count == 0);
		}

		/*[Test(ShouldFail=true)]
		static void TestCircularBufferFail()
		{
			CircularBuffer<int> ints = scope .(5) { 1, 2, 3 };
#unwarn
			let s = ints[5];
		}*/

		[Test]
		static void TestCompressionStream()
		{
			MemoryStream mem = scope .();
			{
				CompressionStream comp = scope .(mem, .BEST_COMPRESSION, false);

				comp.Write(5, 18);
				Test.Assert(comp.WriteStrSized32("I am a String. I am indeed a String. A very nice one.") case .Ok);
				Test.Assert(comp.Flush() case .Ok);
				Test.Assert(comp.Write(uint16[16](1, 2000, 3, 168, 35, 243, 999, 32, 5566, 53, 1, 1, 35676, 7, 1, 999)) case .Ok);
				Test.Assert(comp.Close() case .Ok);
			}

			Test.Assert(mem.Position != 0);
			Test.Assert(mem.Length != 0);
			mem.Position = 0;

			{
				// Check the first bit if the original data
				let orig = uint8[37](5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 53, 0, 0, 0, (.)'I', (.)' ', (.)'a', (.)'m', (.)' ', (.)'a', (.)' ', (.)'S', (.)'t', (.)'r', (.)'i', (.)'n', (.)'g', (.)'.', (.)' ');
				uint8[107] buffer = .();
				Test.Assert(Compression.Decompress(mem.[Friend]mMemory, buffer) case .Ok(107));
				for (let i < 37)
				{
					Test.Assert(buffer[i] == orig[i]);
				}
			}

			{
				CompressionStream dcom = scope .(mem, .Decompress, false, default /* should care about this */);

				let read = dcom.Read<uint8[18]>();
				Test.Assert(read case .Ok(uint8[18](5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5))); // TODO: ADLER check fails for some reason!
				/*for (let i < 18)
					Test.Assert(dcom.Read<uint8>() case .Ok(5));*/
				String s = scope .();
				Test.Assert(dcom.ReadStrSized32(13, s) case .Ok);
				Test.Assert(s == "I am a String");
				Test.Assert(dcom.Read<uint16[16]>() case .Ok(uint16[16](1, 2000, 3, 168, 35, 243, 999, 32, 5566, 53, 1, 1, 35676, 7, 1, 999)));
				Test.Assert(dcom.Close() case .Ok);
			}
		}
	}
}
