# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/document'
require 'hexapdf/type/acro_form/java_script_actions'

describe HexaPDF::Type::AcroForm::JavaScriptActions do
  before do
    @klass = HexaPDF::Type::AcroForm::JavaScriptActions
    @action = {S: :JavaScript}
  end

  describe "formatting" do
    it "returns the original value if the formatting action can't be processed" do
      @action[:JS] = 'Unknown();'
      @klass.apply_formatting("10", @action)
    end

    describe "AFNumber_Format" do
      before do
        @value = '1234567.898765'
        @action[:JS] = ''
      end

      def assert_format(arg_string, result_value, result_color)
        @action[:JS] = "AFNumber_Format(#{arg_string});"
        value, text_color = @klass.apply_formatting(@value, @action)
        assert_equal(result_value, value)
        result_color ? assert_equal(result_color, text_color) : assert_nil(text_color)
      end

      it "respects the set number of decimals" do
        assert_format('0, 2, 0, 0, "E", false', "1.234.568E", "black")
        assert_format('2, 2, 0, 0, "E", false', "1.234.567,90E", "black")
      end

      it "respects the digit separator style" do
        ["1,234,567.90", "1234567.90", "1.234.567,90", "1234567,90"].each_with_index do |result, style|
          assert_format("2, #{style}, 0, 0, \"\", false", result, "black")
        end
      end

      it "respects the negative value styling" do
        @value = '-1234567.898'
        [["-E1234567,90", "black"], ["E1234567,90", "red"], ["(E1234567,90)", "black"],
         ["(E1234567,90)", "red"]].each_with_index do |result, style|
          assert_format("2, 3, #{style}, 0, \"E\", true", result[0], result[1])
        end
      end

      it "respects the specified currency string and position" do
        assert_format('2, 3, 0, 0, " E", false', "1234567,90 E", "black")
        assert_format('2, 3, 0, 0, "E ", true', "E 1234567,90", "black")
      end

      it "does nothing to the value if the JavasSript method could not be determined " do
        assert_format('2, 3, 0, 0, " E", false, a', "1234567.898765", nil)
      end
    end
  end

  describe "calculation" do
    before do
      @doc = HexaPDF::Document.new
      @form = @doc.acro_form(create: true)
      @form.create_text_field('text')
      @field1 = @form.create_text_field('text.1')
      @field1.field_value = "10"
      @field2 = @form.create_text_field('text.2')
      @field2.field_value = "20"
      @field3 = @form.create_text_field('text.3')
      @field3.field_value = "30"
    end

    it "returns nil if the calculation action is not a JavaScript action" do
      @action[:S] = :GoTo
      assert_nil(@klass.calculate(@form, @action))
    end

    it "returns nil if the calculation action contains unknown JavaScript" do
      @action[:JS] = 'Unknown();'
      assert_nil(@klass.calculate(@form, @action))
    end

    describe "predefined calculations" do
      def assert_calculation(function, fields, value)
        fields = fields.map {|field| "\"#{field.full_field_name}\"" }.join(", ")
        @action[:JS] = "AFSimple_Calculate(\"#{function}\", new Array(#{fields}));"
        assert_equal(value, @klass.calculate(@form, @action))
      end

      it "can sum fields" do
        assert_calculation('SUM', [@field1, @field2, @field3], "60")
      end

      it "can average fields" do
        assert_calculation('AVG', [@field1, @field2, @field3], "20")
      end

      it "can multiply fields" do
        assert_calculation('PRD', [@field1, @field2, @field3], "6000")
      end

      it "can find the minimum field value" do
        assert_calculation('MIN', [@field1, @field2, @field3], "10")
      end

      it "can find the maximum field value" do
        assert_calculation('MAX', [@field1, @field2, @field3], "30")
      end

      it "works with floats" do
        @field1.field_value = "10.54"
        assert_calculation('SUM', [@field1, @field2], "30.54")
      end

      it "returns nil if a field cannot be resolved" do
        @action[:JS] = 'AFSimple_Calculate("SUM", ["unknown"]);'
        assert_nil(@klass.calculate(@form, @action))
      end
    end

    describe "simplified field notation calculations" do
      def assert_calculation(sfn, value)
        @action[:JS] = "/** BVCALC #{sfn} EVCALC **/"
        result = @klass.calculate(@form, @action)
        value ? assert_equal(value, result) : assert_nil(result)
      end

      it "works for additions" do
        assert_calculation('text.1 + text.2 + text.1', "40")
      end

      it "works for substraction" do
        assert_calculation('text.2-text\.1', "10")
      end

      it "works for multiplication" do
        assert_calculation('text.2\* text\.1 * text\.3', "6000")
      end

      it "works for division" do
        assert_calculation('text.2 /text\.1', "2")
      end

      it "works with parentheses" do
        assert_calculation('(text.2 + (text.1*text.3))', "320")
      end

      it "works in a more complex case" do
        assert_calculation('(text.1 + text.2)/(text.3) * text.1', "10")
      end

      it "fails if a referenced field is not a terminal field" do
        assert_calculation('text + text.2', nil)
      end

      it "fails if a referenced field does not exist" do
        assert_calculation('unknown + text.2', nil)
      end

      it "fails if parentheses don't match" do
        assert_calculation('(text.1 + text.2', nil)
      end
    end
  end
end
