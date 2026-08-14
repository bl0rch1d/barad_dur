class SpendSample < ApplicationRecord
  validates :bucket, presence: true, uniqueness: true

  def self.accrue!(amount, at: Time.current)
    bucket = at.beginning_of_hour
    sample = find_or_create_by!(bucket: bucket)
    sample.increment!(:amount, amount)
  end

  def self.bars(count = 14)
    order(:bucket).last(count)
  end
end
