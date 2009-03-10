class Test::Unit::TestCase

  IGNORE_PATTERN = /^(id|created_at|created_on|updated_at|updated_on|created_by|updated_by)$/i

  # This method provides a powerful yet simple way to test model definitions. It
  # verifies that the expected columns are supported, and that certain column
  # properties are enforced... such as validations.
  #
  # There are 2 steps to using this method effectively.
  #
  # 1. Create the column meta data that will drive the test. _This is
  #   accomplished by creating a constant by the name of Columns in your test
  #   class like so:_
  #
  #    <code>
  #    Columns = {
  #      :my_column => {:required => true, :default => "some value" :valid => ["value a", "123"], :invalid => ["a", "12"] },
  #      :another_column => :def_only
  #    }
  #    </code>
  #
  #   Each value should be a symbol of :def_only or a Hash.
  #   The column name should be used as the main key for the outer Hash.
  #   If the value is a Hash, the Hash should contain all the column's meta information to be tested.
  #   If the value is :def_only, we only verify that the model has defined the column... nothing else.
  #
  #   The supported keys are:
  #   * required - Boolean
  #   * default - The expected default value.
  #   * valid - An Array of valid values.
  #   * invalid - An Array of invalid values.
  #
  # 2. Create a test that invokes this method like so: <code> def
  #   test_my_model_definition run_model_tests(MyModel.new, Columns) end </code>
  #
  # A complete sample test case would look like something like this:
  #
  # <code>
  #  class MyModelTest < ActiveSupport::TestCase
  #    Columns = {
  #      :my_column => {:required => true, :default => "some value" :valid => ["value a", "123"], :invalid => ["a", "12"] }
  #    }
  #
  #    def test_my_model_definition
  #      run_model_tests(MyModel.new, Columns)
  #    end
  #  end
  # </code>
  def run_model_tests(obj, columns)
    class_name = obj.class.name
    tested_column_names = []

    columns.each do |name, value|
      tested_column_names << name.to_s
      assert obj.respond_to?(name.to_sym), "The #{class_name} model doesn't support the '#{name}' field!"

      next if value == :def_only

      # verify default values
      val = eval "obj.#{name}"
      if value[:default].blank?
        assert val.blank?, "#{class_name}.#{name} has a value when it should be 'blank'!" unless value[:default].blank?
      else
        assert_not_nil val, "The #{class_name}.#{name} field doesn't have a default value!"
        assert_equal val, value[:default], "Invalid default value for #{class_name}.#{name}!"
      end

      # verify required values
      if value[:required]
        eval "obj.#{name} = nil"
        obj.valid?
        assert obj.columns_with_errors.include?(name),
          "#{class_name}.#{name} is required but passed validations with a nil value"
      end

      # verify required values
      if value[:required]
        eval "obj.#{name} = nil"
        obj.valid?
        assert obj.columns_with_errors.include?(name),
          "#{class_name}.#{name} is required but passed validations with a nil value"
      end

      # verify valid values
      if value[:valid]
        value[:valid].each do |val|
          # verify that assignment works as expected
          eval "obj.#{name} = val"
          actual = eval "obj.#{name}"
          print_val = val.nil? ? "nil" : val.to_s
          print_actual = actual.nil? ? "nil" : actual.to_s

          assert_equal val, actual,
            "#{class_name}.#{name} field value assignment is incorrect!\nexpected: #{print_val}\nactual: #{print_actual}"

          # verify that no errors exist after assignment
          obj.valid?

          assert obj.columns_with_errors.exclude?(name),
            "#{class_name} ##{obj.id} '#{name}' field has errors when it shouldn't!  assigned value: #{print_val}\n#{obj.errors[name]}"
        end
      end

      # verify invalid values
      if value[:invalid]
        value[:invalid].each do |val|
          if val.is_a?(Array)
            msg = val[1]
            val = val[0]
          end

          print_val = val.nil? ? "nil" : val.to_s

          # verify the field has errors after assignment
          eval "obj.#{name} = val"
          obj.valid?
          assert obj.columns_with_errors.include?(name),
            "#{class_name}.#{name} field should have errors! assigned value: #{print_val}"

          # test the error message
          if msg
            m = "The expected error message for #{class_name}.#{name} is not present"
            assert_not_nil obj.errors[name], m
            assert obj.errors[name].include?(msg), m
          end
        end
      end
    end

    # verify that the model does not define columns that haven't been tested
    obj.class.columns.each do |column|
      name = column.name
      next if name.to_s =~ IGNORE_PATTERN
      assert tested_column_names.include?(name), "The #{class_name} is missing a model test for the '#{name}' column"
    end
  end

  # This method provides a powerful yet simple way to test model relationships,
  # simply pass a model instance and the relationship meta data that should be tested.
  #
  # The relationship meta data looks like this:
  #  Relations = {
  #   :belongs_to => [:software]
  #  }
  #
  # This method will also test to ensure that the model doesn't define any
  # relationships not tested.  You can turn this off by passing false for "fail_untested".
  #
  # Note: we may need to add more options for non-standard relationships.
  def run_relationship_tests(obj, relations, fail_untested=true)
    klass = obj.class
    tested_relationships = []

    relations.each do |macro, names|
      next if macro == :suppress_loopback
      names = [names] unless names.is_a?(Array)

      names.each do |name|
        tested_relationships << name
        reflection = klass.reflections[name]

        # test definitions
        msg = "#{klass.name} is missing the #{macro} relationship to #{name}"
        assert_not_nil reflection, msg
        assert reflection.macro == macro, msg

        # check foreign key existence
        if macro == :belongs_to
          # verify the foreign key has been setup as an attribute on the model
          fk_name = reflection.options[:foreign_key] || reflection.association_foreign_key
          assert obj.respond_to?(fk_name),
            "#{klass.name} is missing the '#{fk_name}' field which maps to #{name}"

          # verify the parent table maps back to me
          parent_klass = eval reflection.class_name
          parent_reflection_tables = []
          parent_klass.reflections.each {|k,v| parent_reflection_tables << v.table_name }
          assert parent_reflection_tables.include?(klass.table_name),
            "#{parent_klass.name} is missing a relationship that points to #{klass.table_name}"
        end

        if relations[:suppress_loopback].nil? || relations[:suppress_loopback].exclude?(name)
          # test child relations back to me
          # testing here and not recursively so a single test doesn't spawn a system wide check
          if macro == :has_many || macro == :has_one
            child_attr_name = klass.table_name.downcase.singularize.to_sym
            child_klass = eval(reflection.options[:class_name] || reflection.table_name.classify)
            child_reflection = child_klass.reflections[child_attr_name]

            # test relationship definitions back to me
            msg = "#{child_klass.name} is missing the belongs_to relationship to #{child_attr_name}"
            assert_not_nil child_reflection, msg
            assert child_reflection.macro == :belongs_to, msg

            # test child foreign key field that maps back to me
            child_obj = child_klass.new
            assert child_obj.respond_to?(reflection.primary_key_name),
              "#{child_klass.name} is missing the '#{reflection.primary_key_name}' field which maps to #{child_attr_name}"
          elsif macro == :has_and_belongs_to_many
            # test that my child also has me as child
            child_attr_name = klass.table_name.downcase.to_sym
            child_klass = eval(reflection.options[:class_name] || reflection.table_name.classify)
            child_reflection = child_klass.reflections[child_attr_name]

            # test relationship definitions back to me
            msg = "#{child_klass.name} is missing the has_and_belongs_to_many relationship to #{child_attr_name}"
            assert_not_nil child_reflection, msg
            assert child_reflection.macro == :has_and_belongs_to_many, msg
          end
        end

      end
    end

    # verify that the model does not define relationships that haven't been tested
    if fail_untested
      klass.reflections.each do |name, value|
        assert tested_relationships.include?(name),
          "#{klass.name} is missing a relationship test for: #{value.macro} #{name}"
      end
    end
  end

end
