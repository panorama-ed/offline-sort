require 'spec_helper'

describe OfflineSort::Sorter do
  describe "#sort" do
    subject { offline_sorter_instance.sort.to_a }

    let(:offline_sorter_instance) do
      described_class.new(enumerable, chunk_size: entries_per_chunk, &sort)
    end

    let(:entries_per_chunk) { 900 }
    let(:count) { 10000 }
    let(:enumerable) { arrays }
    let(:sort) { array_sort }
    let(:array_sort) { Proc.new { |arr| arr[2] } }
    let(:arrays) do
      count.times.map do |index|
        [SecureRandom.hex, index, SecureRandom.hex]
      end
    end

    shared_examples "a correct offline sort" do
      let(:unsorted) { enumerable.dup }

      it "writes out to disk" do
        expect(Tempfile).to receive(:open).at_least(:once).and_call_original
        subject
      end

      shared_examples "produces a sorted result" do
        it "produces the same sorted result as an in-memory sort" do
          expect(unsorted.sort_by(&sort)).to eq(subject)
        end

        context "closing tempfiles" do
          it "closes all tempfiles" do
            close_count = 0
            allow_any_instance_of(Tempfile).
              to receive(:close) { close_count += 1 }

            expected_number_of_tempfiles =
              (count.to_f / entries_per_chunk).ceil

            # The case where we don't write to disk because there's only
            # one chunk
            if expected_number_of_tempfiles == 1
              expected_number_of_tempfiles = 0
            end

            subject
            expect(close_count).to eq(expected_number_of_tempfiles)
          end
        end

        context "when sorted twice" do
          subject { offline_sorter_instance.sort }

          it "produces the same result both times" do
            expect(subject.to_a).to eq(subject.to_a)
          end

          it "only calls sort the first time" do
            offline_sort = offline_sorter_instance.sort
            in_memory_sort = unsorted.sort_by(&sort)
            # By clearing the enumerable, and then asserting that the offline
            # sort has the same result as the in memory sort, we are asserting
            # that the offline sort must have cached a value derived from the
            # enumerable, and is not caculating anything based on the to_a
            # call.
            enumerable.clear
            expect(offline_sort.to_a).to eq(in_memory_sort)
            # This assertion is validating that we did, in fact, clear the
            # enumerable such that if we now try to offline sort, we have no
            # elements left in the enumerable.
            expect(offline_sorter_instance.sort.to_a).to eq([])
          end
        end
      end

      context "when the number of entries is smaller than the chunk size" do
        let(:count) { entries_per_chunk - 1 }

        it "does not write out to disk" do
          expect(Tempfile).not_to receive(:open)
          subject
        end

        it_behaves_like "produces a sorted result"
      end

      context "when the number of entries is exactly the chunk size" do
        let(:count) { entries_per_chunk }

        it "does not write out to disk" do
          expect(Tempfile).not_to receive(:open)
          subject
        end

        it_behaves_like "produces a sorted result"
      end

      it_behaves_like "produces a sorted result"
    end

    let(:hashes) do
      count.times.map do |index|
        { 'a' => SecureRandom.hex, 'b' => index, 'c' => SecureRandom.hex }
      end
    end

    let(:hash_sort_key) { 'c' }
    let(:hash_sort) { Proc.new { |hash| hash[hash_sort_key] } }

    context "with arrays" do
      it_behaves_like "a correct offline sort"

      context "with multiple sort keys" do
        it_behaves_like "a correct offline sort" do
          let(:enumerable) do
            count.times.map do |index|
              [index.round(-1), index, SecureRandom.hex]
            end.shuffle
          end
          let(:sort) { Proc.new { |arr| [arr[0], arr[1]] } }
        end
      end
    end

    context "hashes" do
      it_behaves_like "a correct offline sort" do
        let(:enumerable) { hashes }
        let(:sort) { hash_sort }
      end

      context "with multiple sort keys" do
        it_behaves_like "a correct offline sort" do
          let(:enumerable) do
            count.times.map do |index|
              { 'a' => index.round(-1), 'b' => index, 'c' => SecureRandom.hex }
            end.shuffle
          end
          let(:sort) { Proc.new { |hash| [hash['a'], hash['c']] } }
        end
      end
    end
  end
end

