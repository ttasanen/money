module MoneyColumn
  module ActiveRecordHooks
    def self.included(base)
      base.extend(ClassMethods)
    end

    def reload(*)
      clear_money_column_cache
      super
    end

    def initialize_dup(*)
      @money_column_cache = {}
      super
    end

    private

    def clear_money_column_cache
      @money_column_cache.clear if persisted?
    end

    def init_internals
      @money_column_cache = {}
      super
    end

    module ClassMethods
      def money_column(*columns, currency_column: nil, currency: nil, currency_read_only: false)
        raise ArgumentError, 'cannot set both currency_column and a fixed currency' if currency && currency_column

        if currency
          currency_object = Money::Currency.find!(currency).to_s
        elsif currency_column
          clear_cache_on_currency_change(currency_column)
        else
          raise ArgumentError, 'must set one of :currency_column or :currency options'
        end

        columns.flatten.each do |column|
          if currency_read_only || currency
            attribute(column, MoneyColumn::Type.new)
            money_column_reader(column, currency_column, currency_object)
            money_column_writer(column, currency_column, currency_object)
          else
            composed_of(
              column.to_sym,
              class_name: 'Money',
              mapping: [[column.to_s, 'value'], [currency_column.to_s, 'currency']],
              converter: Proc.new { |value| value.to_money },
              allow_nil: true,
            )
          end
        end
      end

      private

      def clear_cache_on_currency_change(currency_column)
        return unless currency_column
        define_method "#{currency_column}=" do |value|
          @money_column_cache.clear
          super(value)
        end
      end

      def money_column_reader(column, currency_column, currency_object)
        define_method column do
          return @money_column_cache[column] if @money_column_cache[column]
          return unless value = read_attribute(column)
          iso = currency_object || try(currency_column)
          @money_column_cache[column] = Money.new(value, iso)
        end
      end

      def money_column_writer(column, currency_column, currency_iso)
        define_method "#{column}=" do |money|
          if money.blank?
            write_attribute(column, nil)
            return @money_column_cache[column] = nil
          end
          money = money.to_money

          currency_db = currency_iso || try(currency_column)
          currency_object = Money::Helpers.value_to_currency(currency_db)

          if currency_db && !currency_object.compatible?(money.currency)
            Money.deprecate("[money_column] currency mismatch between #{currency_object} and #{money.currency}.")
          end
          write_attribute(column, money.value)
          @money_column_cache[column] = Money.new(money.value, currency_object)
        end
      end
    end
  end
end
