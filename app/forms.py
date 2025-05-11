from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, SubmitField, BooleanField, IntegerField, SelectField, TimeField, FloatField
from wtforms.validators import DataRequired, Email, Length, EqualTo, ValidationError, NumberRange
from datetime import datetime

from .models import User, Student, Class


class LoginForm(FlaskForm):
    username = StringField('Username', validators=[
                           DataRequired(), Length(1, 50)])
    password = PasswordField('Password', validators=[DataRequired()])
    remember_me = BooleanField('Remember Me')
    submit = SubmitField('Log In')


class RegistrationForm(FlaskForm):
    username = StringField('Username', validators=[
                           DataRequired(), Length(1, 50)])
    email = StringField('Email', validators=[
                        DataRequired(), Email(), Length(1, 100)])
    password = PasswordField('Password', validators=[
                             DataRequired(), Length(min=8)])
    confirm_password = PasswordField(
        'Confirm Password',
        validators=[DataRequired(), EqualTo(
            'password', message='Passwords must match.')]
    )
    submit = SubmitField('Register')

    def validate_username(self, field):
        if User.query.filter_by(username=field.data).first():
            raise ValidationError('Username already in use.')

    def validate_email(self, field):
        if User.query.filter_by(email=field.data).first():
            raise ValidationError('Email already registered.')


class StudentProfileForm(FlaskForm):
    name = StringField('Full Name', validators=[
                       DataRequired(), Length(1, 100)])
    age = IntegerField('Age', validators=[
                       DataRequired(), NumberRange(min=1, max=120)])
    contact = StringField('Contact Number', validators=[
                          DataRequired(), Length(1, 20)])
    submit = SubmitField('Save Profile')

    def validate_contact(self, field):
        # Check if contact number starts with 0 and has 10 digits
        if not (field.data.startswith('0') and field.data.isdigit() and len(field.data) == 10):
            raise ValidationError(
                'Contact number must be 10 digits and start with 0.')


class ClassForm(FlaskForm):
    class_no = IntegerField('Class Number', validators=[
                            DataRequired(), NumberRange(min=1)])
    day_of_week = SelectField('Day of Week', choices=[
        ('monday', 'Monday'),
        ('tuesday', 'Tuesday'),
        ('wednesday', 'Wednesday'),
        ('thursday', 'Thursday'),
        ('friday', 'Friday'),
        ('saturday', 'Saturday'),
        ('sunday', 'Sunday')
    ], validators=[DataRequired()])
    start_time = TimeField('Start Time', validators=[
                           DataRequired()], format='%H:%M')
    end_time = TimeField('End Time', validators=[
                         DataRequired()], format='%H:%M')
    teacher = StringField('Teacher Name', validators=[
                          DataRequired(), Length(1, 100)])
    submit = SubmitField('Save Class')

    def validate_end_time(self, field):
        if self.start_time.data and field.data and self.start_time.data >= field.data:
            raise ValidationError('End time must be after start time.')

    def validate(self, extra_validators=None):
        if not super(ClassForm, self).validate():
            return False

        # Check for time overlap with existing classes
        existing_classes = Class.query.filter_by(
            day_of_week=self.day_of_week.data).all()

        for existing_class in existing_classes:
            # Skip if editing the same class
            if hasattr(self, 'class_id') and self.class_id == existing_class.id:
                continue

            # Check if class number already exists for this day
            if existing_class.class_no == self.class_no.data:
                self.class_no.errors.append(
                    f'Class number {self.class_no.data} already exists for {self.day_of_week.data}.')
                return False

            # Check for time overlap
            if (self.start_time.data < existing_class.end_time and
                    self.end_time.data > existing_class.start_time):
                self.start_time.errors.append(
                    'This time overlaps with an existing class.')
                return False

        return True


class RegistrationRequestForm(FlaskForm):
    class_id = SelectField('Class', coerce=int, validators=[DataRequired()])
    month = SelectField('Month', choices=[
        (1, 'January'), (2, 'February'), (3, 'March'), (4, 'April'),
        (5, 'May'), (6, 'June'), (7, 'July'), (8, 'August'),
        (9, 'September'), (10, 'October'), (11, 'November'), (12, 'December')
    ], coerce=int, validators=[DataRequired()])
    submit = SubmitField('Request Registration')

    # Remove the custom validate method or update it to accept extra_validators
    # Either remove this entirely:
    # def validate(self):
    #     if not super().validate():
    #         return False
    #     return True

    # Or update it to accept the extra_validators parameter:
    def validate(self, extra_validators=None):
        if not super(RegistrationRequestForm, self).validate():
            return False
        return True


class SettingsForm(FlaskForm):
    fee_per_session = FloatField('Fee Per Session', validators=[
                                 DataRequired(), NumberRange(min=0)])
    submit = SubmitField('Update Settings')
